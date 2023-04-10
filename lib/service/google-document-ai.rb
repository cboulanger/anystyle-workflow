require './lib/service/base'
require 'grim'

# monkey-patch File to work around bug in Grim
# @see https://github.com/jonmagic/grim/issues/41
class File
  class << self
    alias exists? exist?;
  end
end

# How to use this service:
# 0. Install the gem (is not part of the bundle since it might not be needed. ): `gem install google-cloud-document_ai`
# 1. Set up a Google DocumentAi project & processor at https://cloud.google.com
# 2. Configure the ... environment vars in `.env` accordingly
# 3. install CloudCLI as per https://cloud.google.com/sdk/docs/install
# 4. initialize and authenticate with `gcloud init`
# 5. authenticate this client with `gcloud auth application-default login`
# 6. set the `GOOGLE_APPLICATION_CREDENTIALS` env var in `.env` to the path of the credentials file
# @see https://cloud.google.com/ruby/docs/reference/google-cloud-document_ai/latest/AUTHENTICATION
# @see https://cloud.google.com/ruby/docs/reference/google-cloud-document_ai/latest/Google-Cloud-DocumentAI
# @see https://www.rubydoc.info/gems/google-cloud-document_ai/1.2.1
module Service
  class GoogleDocumentAi < Base

    def self.type
      OCR
    end

    def initialize
      require "google/cloud/document_ai"
      @project_id = ENV['GOOGLE_CLOUD_PROJECT_ID']
      @location_id = ENV['GOOGLE_CLOUD_LOCATION_ID']
      @processor_id = ENV['GOOGLE_CLOUD_PROCESSOR_ID']
    end

    ##
    # Document AI quickstart
    # @see https://cloud.google.com/document-ai/docs/libraries#client-libraries-install-ruby
    # @param file_path [String] Path to Local File (e.g. "invoice.pdf")
    #
    def process(file_path, first_page: nil, last_page:nil, &block)
      client = Google::Cloud::DocumentAI.document_processor_service
      name = client.processor_path(
        project: @project_id,
        location: @location_id,
        processor: @processor_id
      )
      pdf = Grim.reap(file_path)
      tmp_file = 'tmp/google-ocr.png'
      # return the enumerator which yields the text of each of the PDF document's pages
      Enumerator.new do |y|
        pdf.each_with_index do |page, i|
          next if first_page && (i + 1  < first_page)
          next if last_page && (i + 1 > last_page)

          page.save(tmp_file)

          request = Google::Cloud::DocumentAI::V1::ProcessRequest.new(
            skip_human_review: true,
            name: name,
            raw_document: {
              content: File.binread(tmp_file),
              mime_type: 'image/png'
            }
          )
          response = client.process_document request
          y.yield response.document.text
        end
      end.each(&block)
    end
  end
end
