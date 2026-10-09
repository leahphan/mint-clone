require "test_helper"

class CsvTableTest < ActiveSupport::TestCase
  test "reads the headerless TD chequing export: quoted, LF line endings" do
    table = CsvTable.parse(file_fixture("td_chequing.csv").read)

    assert_equal [ ",", 5, false, 71 ], [ table.delimiter, table.column_count, table.header?, table.rows.size ]
    assert_equal [ 1, [ "2026-09-09", "KAFU SEMO AND   _F", "130", nil, "2219.22" ] ], [ table.rows.first.line, table.rows.first.fields ]
    assert_equal 71, table.rows.last.line
  end

  test "reads the headerless TD Visa export: unquoted, CRLF line endings" do
    table = CsvTable.parse(file_fixture("td_visa.csv").read)

    assert_equal [ ",", 5, false, 52 ], [ table.delimiter, table.column_count, table.header?, table.rows.size ]
    assert_equal "10/05/2026,KAFU AUTO/KOPRD4ILT1,20.00,,1718.48", table.rows.first.text
    assert_equal 52, table.rows.last.line
  end

  test "detects a header row and normalizes its names" do
    table = CsvTable.parse("Transaction Date,Description,Amount ($),CAD$\n2026-09-01,Loblaws,-54.32,100.00\n")

    assert table.header?
    assert_equal [ "transaction date", "description", "amount", "cad" ], table.normalized_header
    assert_equal 1, table.rows.size
  end

  { ";" => "semicolon", "\t" => "tab", "|" => "pipe" }.each do |delimiter, name|
    test "detects a #{name} delimiter" do
      table = CsvTable.parse([ "2026-09-01", "Loblaws, Queen St", "-54.32" ].join(delimiter) + "\n" + [ "2026-09-02", "Payroll", "2500.00" ].join(delimiter) + "\n")

      assert_equal [ delimiter, 3 ], [ table.delimiter, table.column_count ]
      assert_equal "Loblaws, Queen St", table.rows.first.fields[1]
    end
  end

  test "counts physical lines across blank lines, a byte-order mark, and quoted fields spanning lines" do
    table = CsvTable.parse("﻿2026-09-01,Loblaws,-54.32\n\n2026-09-02,\"Two\nlines\",-1.00\n2026-09-03,Payroll,2500.00\n")

    assert_equal [ 1, 3, 5 ], table.rows.map(&:line)
    assert_equal "Two\nlines", table.rows.second.fields[1]
  end

  test "keeps rows with the wrong number of fields so they can be reported" do
    table = CsvTable.parse("2026-09-01,Loblaws,-54.32\n2026-09-02,Payroll\n2026-09-03,Coffee,-4.50\n")

    assert_equal [ 3, 2, 3 ], table.rows.map { |row| row.fields.size }
  end

  test "the fingerprint describes the layout, not the contents" do
    chequing = CsvTable.parse(file_fixture("td_chequing.csv").read)
    later_chequing = CsvTable.parse(file_fixture("td_chequing.csv").readlines.last(20).join)
    visa = CsvTable.parse(file_fixture("td_visa.csv").read)

    assert_equal chequing.fingerprint, later_chequing.fingerprint
    assert_not_equal chequing.fingerprint, visa.fingerprint
  end

  test "the fingerprint doesn't change when an export has no deposits" do
    with_deposit = CsvTable.parse("2026-09-01,Loblaws,54.32,,100.00\n2026-09-02,Payroll,,2500.00,2600.00\n")
    without_deposit = CsvTable.parse("2026-09-01,Loblaws,54.32,,100.00\n2026-09-02,Coffee,4.50,,95.50\n")

    assert_equal with_deposit.fingerprint, without_deposit.fingerprint
  end

  {
    "an empty file" => [ "  \n", "The file is empty." ],
    "non-UTF-8 content" => [ "2026-09-01,Caf\xE9,-4.50\n".b, "The file must be UTF-8 text." ],
    "too few columns" => [ "2026-09-01 Loblaws\n2026-09-02 Payroll\n", "We couldn't find the columns in this file." ],
    "malformed CSV" => [ %(2026-09-01,"Loblaws,-54.32\n2026-09-02,Payroll,2500.00\n), "The file isn't valid CSV" ]
  }.each do |problem, (content, message)|
    test "rejects #{problem}" do
      error = assert_raises(CsvTable::Error) { CsvTable.parse(content) }
      assert error.message.start_with?(message), error.message
    end
  end
end
