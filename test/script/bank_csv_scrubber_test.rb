require "test_helper"
require "csv"
require Rails.root.join("script/bank_csv_scrubber").to_s

class BankCsvScrubberTest < ActiveSupport::TestCase
  # Headerless, CRLF, debit/credit/balance columns, like a TD chequing export.
  TD_CSV = [
    "09/01/2026,SQ *JOES CAFE TORONTO ON #0382,4.50,,1995.50",
    "09/02/2026,E-TRANSFER TO JOHN SMITH,100.00,,1895.50",
    "09/03/2026,PAYROLL DEP ACME CORP 1234567,,2500.00,4395.50",
    "09/04/2026,\"SQ *JOES CAFE TORONTO ON #0382\",4.50,,4391.00",
    "09/05/2026,INTERAC E-TRANSFER FROM jane.doe@gmail.com,,50.00,4441.00",
    "09/06/2026,PAYPAL *SPOTIFY 416-555-0199,11.99,,4429.01",
    "09/07/2026,CARD 4520********1234 BOBS DINER,2.10,,4426.91"
  ].join("\r\n") + "\r\n"

  # Headered, every field quoted, one signed amount column and a running balance.
  SIGNED_CSV = <<~CSV
    "Date","Description","Amount","Balance"
    "2026-09-01","TST* JOES PIZZA, TORONTO","-25.00","975.00"
    "2026-09-02","AMZN Mktp CA*2K3L45PQ1","-40.00","935.00"
    "2026-09-03","Payroll ACME CORP","2,500.00","3,435.00"
    "2026-09-04","TST* JOES PIZZA, TORONTO","-25.00","3,410.00"
  CSV

  setup do
    @dir = Dir.mktmpdir
    @outputs = []
  end

  teardown do
    FileUtils.rm_f(@outputs)
    FileUtils.remove_entry(@dir)
  end

  test "keeps a headerless TD-style file's layout, dates, amounts, and balances" do
    output = scrub(TD_CSV)

    assert_equal TD_CSV.count("\r\n"), output.count("\r\n")
    original_rows, scrubbed_rows = CSV.parse(TD_CSV), CSV.parse(output)
    assert_equal original_rows.map(&:size), scrubbed_rows.map(&:size)
    assert_equal original_rows.map { |row| row.values_at(0, 2, 3, 4) }, scrubbed_rows.map { |row| row.values_at(0, 2, 3, 4) }
    assert_match(/\A09\/04\/2026,"SQ \*[A-Z]+ CAFE TORONTO ON #0382",4\.50,,4391\.00\z/, output.lines[3].chomp)
  end

  test "detects the structure of a headerless file" do
    scrubber = BankCsvScrubber.new(write_input(TD_CSV))

    assert_not scrubber.header?
    assert_equal [ :date, :text, :amount, :amount, :amount ], scrubber.columns.map(&:kind)
    assert_equal [ nil, nil, :debit, :credit, :balance ], scrubber.columns.map(&:role)
  end

  test "keeps a headered file's header, quoting, and quoted delimiters" do
    output = scrub(SIGNED_CSV)
    lines = output.lines

    assert_equal %("Date","Description","Amount","Balance"\n), lines.first
    assert lines.drop(1).all? { |line| line.match?(/\A("[^"]*",){3}"[^"]*"\n\z/) }, output
    assert_match(/\A"2026-09-01","TST\* [A-Z]+ PIZZA, TORONTO","-25.00","975.00"\n\z/, lines[1])
    assert_equal CSV.parse(SIGNED_CSV).map { |row| row.values_at(0, 2, 3) }, CSV.parse(output).map { |row| row.values_at(0, 2, 3) }
  end

  test "maps each real merchant to the same synthetic merchant every time" do
    rows = CSV.parse(scrub(<<~CSV))
      2026-09-01,SQ *JOES CAFE,-4.50
      2026-09-02,SQ *BOBS CAFE,-3.00
      2026-09-03,Joes Cafe,-4.50
      2026-09-04,SQ *JOES CAFE,-4.50
    CSV
    descriptions = rows.map { |row| row[1] }

    assert_equal descriptions[0], descriptions[3]
    assert_not_equal descriptions[0], descriptions[1]
    assert_equal descriptions[0].delete_prefix("SQ *").downcase, descriptions[2].downcase
    assert descriptions.none? { |description| description.match?(/JOES|BOBS/i) }
  end

  test "removes names, emails, phone numbers, and account, card, and reference numbers" do
    output = scrub(<<~CSV)
      2026-09-01,E-TRANSFER TO JOHN SMITH,-100.00
      2026-09-02,INTERAC E-TRANSFER FROM jane.doe@gmail.com,50.00
      2026-09-03,TRANSFER FROM JOHN SMITH,20.00
      2026-09-04,MORTGAGE PAYMENT ACCT 00123-4567890,-1500.00
      2026-09-05,CARD 4520********1234 (416) 555-0199,-9.99
      2026-09-06,BILL PAYMENT CONF A1B2C3D4E5 POSTAL M5V 2T6,-80.00
    CSV

    %w[JOHN SMITH jane.doe gmail 00123 4567890 4520 1234 416 0199 A1B2C3D4E5 M5V].each do |secret|
      assert_not_includes output, secret
    end
    lines = output.lines(chomp: true)
    assert_equal "2026-09-01,E-TRANSFER TO TEST PERSON A,-100.00", lines[0]
    assert_equal "2026-09-02,INTERAC E-TRANSFER FROM person.a@example.com,50.00", lines[1]
    assert_equal "2026-09-03,TRANSFER FROM TEST PERSON A,20.00", lines[2]
    assert_match(/\A2026-09-04,MORTGAGE PAYMENT ACCT \d{5}-\d{7},-1500\.00\z/, lines[3])
    assert_match(/\A2026-09-05,CARD \d{4}\*{8}\d{4} \(555\) 555-0100,-9\.99\z/, lines[4])
  end

  test "replaces identifier columns named in the header" do
    rows = CSV.parse(scrub(<<~CSV))
      Account Type,Account Number,Transaction Date,Cheque Number,Description 1,CAD$
      Chequing,00123-1234567,9/1/2026,101,CHEQUE,-500.00
    CSV

    assert_equal [ "Chequing", "9/1/2026", "CHEQUE", "-500.00" ], rows[1].values_at(0, 2, 4, 5)
    assert_match(/\A\d{5}-\d{7}\z/, rows[1][1])
    assert_not_equal "00123-1234567", rows[1][1]
    assert_match(/\A\d{3}\z/, rows[1][3])
  end

  test "scrubs a preamble row instead of treating it as the header" do
    scrubber = BankCsvScrubber.new(write_input("Account 00123-4567890 JOHN SMITH\n2026-09-01,Coffee,-4.50\n"))
    @outputs << scrubber.output_path

    assert_not scrubber.header?
    assert_no_match(/4567890|JOHN|SMITH/, File.read(scrubber.call) + scrubber.report)
  end

  test "strict mode also replaces city and category words and short reference numbers" do
    line = CSV.parse(scrub("09/01/2026,SQ *JOES CAFE TORONTO ON #0382,4.50,,100.00\n", strict: true)).first[1]

    assert_match(/\ASQ \*[A-Z]+ [A-Z]+ [A-Z]+ ON #\d{4}\z/, line)
    %w[JOES CAFE TORONTO 0382].each { |word| assert_not_includes line, word }
  end

  test "randomizing amounts keeps directions, repeats, and debit/credit balance arithmetic" do
    rows = CSV.parse(scrub(TD_CSV, randomize_amounts: true))
    original = CSV.parse(TD_CSV)

    assert_not_equal original.map { |row| row[2] }, rows.map { |row| row[2] }
    assert_equal original.map { |row| row[2].nil? }, rows.map { |row| row[2].nil? }
    assert_equal rows[0][2], rows[3][2]
    assert_equal BigDecimal("2000.00"), BigDecimal(rows[0][4]) + BigDecimal(rows[0][2]), "opening balance is kept"
    rows.each_cons(2) do |previous, row|
      expected = BigDecimal(previous[4]) - BigDecimal(row[2] || "0") + BigDecimal(row[3] || "0")
      assert_equal expected, BigDecimal(row[4])
    end
  end

  test "randomizing amounts and scrubbing balances keeps signed-amount arithmetic and duplicate rows" do
    csv = <<~CSV
      date,description,amount,balance
      2026-09-01,Coffee,-4.50,95.50
      2026-09-02,Payroll,2500.00,2595.50
      2026-09-02,Payroll,2500.00,2595.50
      2026-09-03,Rent,-1500.00,1095.50
    CSV
    rows = CSV.parse(scrub(csv, randomize_amounts: true, scrub_balances: true)).drop(1)

    assert_not_equal "95.50", rows[0][3]
    assert_equal rows[1], rows[2]
    assert_equal [ true, false, true ], rows.map { |row| row[2].start_with?("-") }.values_at(0, 1, 3)
    [ [ 0, 1 ], [ 2, 3 ] ].each do |previous, current|
      assert_equal BigDecimal(rows[previous][3]) + BigDecimal(rows[current][2]), BigDecimal(rows[current][3])
    end
  end

  test "scrubbing balances keeps the formatting and arithmetic of grouped amounts" do
    rows = CSV.parse(scrub(SIGNED_CSV, scrub_balances: true)).drop(1)
    amount = ->(text) { BigDecimal(text.delete(",")) }

    assert_equal CSV.parse(SIGNED_CSV).drop(1).map { |row| row[2] }, rows.map { |row| row[2] }
    rows.each_cons(2) { |previous, row| assert_equal amount.(previous[3]) + amount.(row[2]), amount.(row[3]) }
    assert_match(/\A\d{1,3}(,\d{3})+\.\d{2}\z/, rows[2][3], "grouped balances stay grouped")
  end

  test "shifting dates keeps their format and the gaps between them" do
    rows = CSV.parse(scrub(TD_CSV, shift_dates: true))
    dates = rows.map { |row| Date.strptime(row[0], "%m/%d/%Y") }

    assert rows.all? { |row| row[0].match?(/\A\d{2}\/\d{2}\/\d{4}\z/) }
    assert_not_equal Date.new(2026, 9, 1), dates.first
    assert_equal (0..6).to_a, dates.map { |date| (date - dates.first).to_i }
  end

  test "keeps a BOM, blank lines, and duplicate rows, so the output still imports" do
    csv = "﻿Date,Description,Amount\n\n2026-09-01,Loblaws #1234,-54.32\n2026-09-01,Loblaws #1234,-54.32\n"
    output = scrub(csv)

    assert output.start_with?("﻿Date,Description,Amount\n\n2026-09-01,")
    import = TransactionCsvImporter.call(create(:account), csv_upload(output))
    assert import.persisted?, import.errors.full_messages.to_sentence
    assert_equal 2, import.rows_imported
  end

  test "never modifies the input file and writes only to the scrubbed-data directory" do
    path = write_input(TD_CSV)
    File.utime(Time.utc(2026, 1, 1), Time.utc(2026, 1, 1), path)
    original_bytes, original_mtime = File.binread(path), File.mtime(path)

    scrubber = BankCsvScrubber.new(path, randomize_amounts: true, shift_dates: true, scrub_balances: true, strict: true)
    @outputs << scrubber.output_path
    scrubber.call

    assert_equal [ original_bytes, original_mtime ], [ File.binread(path), File.mtime(path) ]
    assert_equal [ path ], Dir.children(@dir).map { |name| File.join(@dir, name) }
    assert_equal BankCsvScrubber::OUTPUT_DIR, File.dirname(scrubber.output_path)
    assert_equal Rails.root.join("tmp/scrubbed-bank-data").to_s, BankCsvScrubber::OUTPUT_DIR
    assert File.exist?(scrubber.output_path)
  end

  test "preview reports the structure without writing anything or printing original values" do
    scrubber = BankCsvScrubber.new(write_input(TD_CSV))
    report = scrubber.preview

    assert_not File.exist?(scrubber.output_path)
    assert_includes report, %(delimiter: ",", header: no, columns: 5, data rows: 7)
    assert_includes report, "line endings: CRLF"
    assert_includes report, "3. amount (debit) - kept"
    assert_includes report, "emails: 1"
    %w[JOES JOHN SMITH jane.doe 0199 4520].each { |secret| assert_not_includes report, secret }
  end

  private
    def write_input(content)
      File.join(@dir, "bank-#{SecureRandom.hex(4)}.csv").tap { |path| File.binwrite(path, content) }
    end

    def scrub(content, **options)
      scrubber = BankCsvScrubber.new(write_input(content), **options)
      @outputs << scrubber.output_path
      File.read(scrubber.call, encoding: "UTF-8")
    end
end
