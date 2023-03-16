# frozen_string_literal: true

# rubocop:disable Naming/MethodName
module Model
  module Zotero
    # The model for a Zotero Creator object
    class Creator < ::Model::Model
      ROLES = %i[artist contributor performer composer wordsBy sponsor cosponsor author
                 commenter editor translator seriesEditor bookAuthor counsel programmer
                 reviewedAuthor recipient director scriptwriter producer interviewee interviewer
                 cartographer inventor attorneyAgent podcaster guest presenter castMember].freeze

      attr_accessor :firstName, :lastName, :role
    end

    # The model for a Zotero Item object
    class Item < ::Model::Model
      TYPES = %i[artwork attachment audioRecording bill blogPost book bookSection case computerProgram
                 conferencePaper dictionaryEntry document email encyclopediaArticle film forumPost hearing
                 instantMessage interview journalArticle letter magazineArticle manuscript map newspaperArticle
                 note patent podcast presentation radioBroadcast report statute thesis tvBroadcast
                 videoRecording webpage annotation preprint].freeze

      attr_accessor :title, :abstractNote, :artworkMedium, :medium, :artworkSize, :date, :language,
                    :shortTitle, :archive, :archiveLocation, :libraryCatalog, :callNumber, :url,
                    :accessDate, :rights, :extra, :audioRecordingFormat, :seriesTitle, :volume,
                    :numberOfVolumes, :place, :label, :publisher, :runningTime, :ISBN, :billNumber,
                    :number, :code, :codeVolume, :section, :codePages, :pages, :legislativeBody,
                    :session, :history, :blogTitle, :publicationTitle, :websiteType, :type, :series,
                    :seriesNumber, :edition, :numPages, :bookTitle, :caseName, :court, :dateDecided,
                    :docketNumber, :reporter, :reporterVolume, :firstPage, :versionNumber, :system,
                    :company, :programmingLanguage, :proceedingsTitle, :conferenceName, :DOI,
                    :dictionaryTitle, :subject, :encyclopediaTitle, :distributor, :genre,
                    :videoRecordingFormat, :forumTitle, :postType, :committee, :documentNumber,
                    :interviewMedium, :issue, :seriesText, :journalAbbreviation, :ISSN, :letterType,
                    :manuscriptType, :mapType, :scale, :country, :assignee, :issuingAuthority,
                    :patentNumber, :filingDate, :applicationNumber, :priorityNumbers, :issueDate,
                    :references, :legalStatus, :episodeNumber, :audioFileType, :presentationType,
                    :meetingName, :programTitle, :network, :reportNumber, :reportType, :institution,
                    :nameOfAct, :codeNumber, :publicLawNumber, :dateEnacted, :thesisType, :university,
                    :studio, :websiteTitle, :repository, :archiveID, :citationKey
    end
  end
end
