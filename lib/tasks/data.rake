# frozen_string_literal: true

require 'dotenv/tasks'
require 'marc'

namespace :findit do
  namespace :data do
    require_relative './data/fetch'
    include FindIt::Data::Fetch

    require_relative './data/providers'

    require_relative './data/delete'
    include FindIt::Data::Delete

    RECORD_PROVIDERS.each do |provider, config|
      namespace :index do
        desc "Index MARC records from #{config['record_provider_facet']}"
        task provider, [:filename] => :environment do |_task, args|
          config_dir = Rails.root.join('lib/tasks/data/config')
          config_file_list = config['traject_configuration_files']
                             .map { |config_file| "-c #{config_dir}/#{config_file}.rb" }
                             .join ' '
          command = 'bundle exec traject'\
                    " -c #{config_dir}/config.rb"\
                    " #{config_file_list}"\
                    " -s processing_thread_pool=#{num_threads(Rails.env, config['needs_many_processing_threads'])}"\
                    " -I #{config_dir}"\
                    " -s solr.url=#{Blacklight.connection_config[:url]}"\
                    " #{Rails.root.join(args[:filename])}"
          system command
        end
      end
      namespace :delete do
        desc "Delete all solr records from #{config['record_provider_facet']}"
        task provider => :environment do
          FindIt::Data::Delete.by_record_provider_facet config['record_provider_facet']
        end
      end
    end

    RECORD_PROVIDERS.select { |_provider, config| config['fetch_method'] }
                    .each do |provider, config|
      namespace :fetch do
        desc "Fetch MARC record from #{config['record_provider_facet']}"
        task provider => :environment do
          method = FindIt::Data::Fetch.method(config['fetch_method'])
          method.call(config)
        end
      end
      namespace :fetch_and_index do
        desc "Fetch and index MARC records from #{config['record_provider_facet']}"
        task provider => :environment do
          method = FindIt::Data::Fetch.method(config['fetch_method'])
          filenames = method.call(config)
          filenames.map do |filename|
            Thread.new do
              execute_index_task provider: provider, filename: filename
            end
          end.each(&:join)
        end
      end
    end

    namespace :fetch_and_index do
      desc 'Fetch and index from all sources that can be fetched automatically'
      task all: :environment do
        RECORD_PROVIDERS.select { |_provider, config| config['fetch_method'] }
                        .sort_by { |_provider, config| config['needs_many_processing_threads'] ? 0 : 1 }
                        .map do |provider, _config|
          Thread.new do
            Rake::Task["findit:data:fetch_and_index:#{provider}"].execute
          end
        end.each(&:join)
        Rake::Task['findit:data:commit'].execute
      end
    end

    namespace :index do
      desc 'Index sample data (perhaps for running tests)'
      task sample: :environment do
        fixture_providers = %w[eg eg_online gale oclc]
        fixture_providers.each do |provider|
          execute_index_task provider: provider, filename: fixture_filename(provider)
        end
        Rake::Task['findit:data:commit'].execute
      end
    end
    task commit: :environment do
      system("bundle exec traject -x commit -s solr.url=#{Blacklight.connection_config[:url]} "\
             '-s solr_writer.http_timeout=1200 '\
             "-c #{Rails.root.join('lib/tasks/data/config/config.rb')}")
    end

    task crossref: :environment do
      # TODO: user agent
      # TODO: cache
      # TODO: follow all of the "NICE" rules for crossref api
      File.readlines(Rails.root.join('config/issns.txt')).each do |issn|
        json = URI.parse("https://api.crossref.org/works?filter=issn:#{issn}&rows=1000").read
        result = JSON(json)
        result['message']['items'].each do |article|
          next unless article['title']
            puts article['title'].first
            document = {
              id: article['DOI'],
              format: article['type'],
              abstract_display: ActionController::Base.helpers.strip_tags(article['abstract']),
              is_electronic_facet: 'Online',
              publisher_display: article['publisher'],
              publisher_t: article['publisher'],
              pub_date: article['created']['date-parts'].first[0],
              record_provider_facet: 'Open access',
              record_source_facet: 'Open access',
              title_display: article['title'].first,
              title_t: article['title'].first,
              url_fulltext_display: article['link'].first['URL']
            }
            solr = RSolr.connect url: ENV['SOLR_URL']
            solr.add document
  
          end
        end
      end
    end
  end
end

def num_threads(environment, needs_many_processing_threads)
  if environment == 'indexer'
    needs_many_processing_threads ? 5 : 1
  else
    3
  end
end

def execute_index_task(provider:, filename:)
  Rake::Task["findit:data:index:#{provider}"].execute(filename: filename)
end

def fixture_filename(provider)
  "spec/fixtures/files/#{provider}.mrc"
end
