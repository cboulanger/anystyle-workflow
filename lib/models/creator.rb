# frozen_string_literal: true

#module Model
  class Creator
    include ActiveGraph::Node
    property :display_name
    property :family
    property :given
    property :literal
    property :dateOfBirth

    has_many :out, :created, model_class: :Work, rel_class: :CreatorOf

    def get_display_name
      unless literal.nil?
        return literal
      end
      if family.nil? && given.nil?
        family
      else
        "#{family}, #{given}"
      end
    end

    def save(*args)
      super(*args)
      self.display_name = get_display_name
    end
  end
#end

