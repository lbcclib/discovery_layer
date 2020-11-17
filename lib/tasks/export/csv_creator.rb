# frozen_string_literal: true

require 'csv'
require 'library_stdnums'

# Creates CSV files based on data from solr
class CsvCreator
  def initialize(config)
    get_config_from_file config
    solr = RSolr.connect url: ENV['SOLR_URL']
    response = solr.get 'select', params: { q: config['query'], fl: @fl, facet: false, rows: 2_000_000 }
    @docs = response['response']['docs']
  end

  def write
    CSV.open('test.csv', 'wb', col_sep: @delimiter, headers: @headers, write_headers: @write_headers) do |csv|
      @docs.each do |doc|
        extract_isbns_from_doc(doc).each do |isbn|
          row = [isbn]
          row.concat(@non_isbn_fl.map { |f| doc[f].first })
          csv << row
        end
      end
    end
  end

  private

  def get_config_from_file(config)
    @delimiter = config['delimiter'] || ','
    @headers = %w[ISBN]
    @headers.concat(config['non_isbn_solr_fields']&.map { |f| f['label'] })
    @isbn_fl = config['fields_containing_isbns']
    @non_isbn_fl = config['non_isbn_solr_fields'] ? config['non_isbn_solr_fields'].map { |f| f['field'] } : []
    @fl = @isbn_fl + @non_isbn_fl
    @write_headers = config['include_header_row'] || false
  end

  def extract_isbns_from_doc(doc)
    isbns = []
    @isbn_fl.each do |field|
      next unless doc[field]

      isbns.concat(doc[field].map { |isbn| ::StdNum::ISBN.normalize isbn})
    end
    isbns.uniq
  end
end
