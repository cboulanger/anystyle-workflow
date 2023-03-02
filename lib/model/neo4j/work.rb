module Model
  module Neo4J
    class Work
      include ActiveGraph::Node
      property :display_name
      property :type
      property :title
      property :date
      # property :isbn
      property :note
      property :doi
      property :imported

      has_many :in, :creators, model_class: :Creator, rel_class: :CreatorOf
      has_many :out, :citations, model_class: :Work, rel_class: :Citation
      has_one :out, :container, model_class: [:Journal, :EditedBook], rel_class: :ContainedIn

      def initialize(args = nil)
        super(args)
      end

      def get_display_name
        name_ = first_creator_name
        display_name_ = name_.nil? ? '' : "#{name_}, "
        title_ = self.title.split(' ').slice(0, 10).join(' ')
        date_ = (self.date.nil? ? '' : self.date.to_s)
        "#{display_name_}#{title_} (#{date_})"
      end

      def first_creator_name
        if creators.length > 0
          creators.first['family'] || creators.first.literal
        else
          nil
        end
      end

      def save(*args)
        super(*args)
        self.display_name = get_display_name
      end
    end

    class EditedBook < Work
      has_many :in, :works, model_class: :Work, rel_class: :ContainedIn
    end

    class Journal
      include ActiveGraph::Node
      property :title
      property :display_name
      has_many :in, :works, model_class: :Work, rel_class: :ContainedIn
    end
  end
end