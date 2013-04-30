# -*- encoding : utf-8 -*-
require_dependency 'chunks/chunk'

module Chunks
  class Include < Reference
#    attr_reader :options
    cattr_reader :options
    @@options = [ :include_name, :view, :item, :type, :size, :title, :hide, :show, :include, :structure ].
      inject({}) do |hash, key| hash[key] = nil; hash end
    
#    attr_reader :options
    unless defined? INCLUDE_CONFIG
      #  {{+name|attr:val;attr:val;attr:val}}
      #  Groups: $1, everything (less {{}}), $2 name, $3 options
      INCLUDE_CONFIG = {
        :class     => Include,
        :prefix_re => '\\{\\{',
        :rest_re   =>  /^([^\}]*)\}\}/,
        :idx_char  => '{'
      }
    end

    def self.config() INCLUDE_CONFIG end

    def initialize match, card_params, params
      super
      self.name = parse match, params
      self
    end

    def parse match, params

      in_brackets = params[2]
      #warn "parse include [#{in_brackets}] #{match}, #{params.inspect}"
      name, opts = in_brackets.split('|',2)
      result = case name = name.to_s.strip
        when /^\#\#/ ; '' # invisible comment
        when /^\#/   ;  "<!-- #{CGI.escapeHTML in_brackets} -->"
        when ''      ; '' # no name
        else
          @options = @@options.clone.merge :include_name => name, :include => in_brackets #yuck, need better name (this is raw stuff)

          @configs = Hash.new_from_semicolon_attr_list opts

          @options[:style] = @configs.inject({}) do |styles, pair| key, value = pair
            @options.key?(key.to_sym) ? @options[key.to_sym] = value : styles[key] = value
            styles
          end.map do |style_name,style|
            CGI.escapeHTML "#{style_name}:#{style};"
          end * ''
            
          :standard_inclusion
      end
      
      if result == :standard_inclusion
        name
      else
        @process_chunk = result
        nil
      end
    end

    def inspect
      "<##{self.class}:n[#{@name}] p[#{@process_chunk}] txt:#{@text}>"
    end

    def process_chunk
      return @process_chunk if @process_chunk

      referee_name
      if view = @options[:view]
        view = view.to_sym
      end

      @processed = yield @options # this is not necessarily text, sometimes objects for json
    end

    def replace_reference old_name, new_name
      replace_name_reference old_name, new_name

      ( configs = @configs.to_semicolon_attr_list ).blank? or
        configs = "|" + configs
      @text = '{{' + @name.to_s + configs + '}}'
    end

  end
end
