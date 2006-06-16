# This software is released under the MIT license
#
# Copyright (c) 2006 Stefan Kaes

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class ActiveRecord::Base
  class << self

    # make validate_find_options accept :piggy
    VALID_FIND_OPTIONS << :piggy
    
    alias_method :old_construct_finder_sql, :construct_finder_sql
  
    # redefine construct_finder_sql to support piggy back option
    def construct_finder_sql(options) #:nodoc:
      add_piggy_back!(options)
      old_construct_finder_sql(options)
    end
    
    alias_method :old_set_readonly_option!, :set_readonly_option!
    
    # records with piggy backed attributes are always read only.
    def set_readonly_option!(options) #:nodoc:
      if options[:piggy]
        options[:readonly] = true
      else
        old_set_readonly_option!(options)
      end
    end
    
    # declare piggy back for current AR class. Calls look like
    #
    #   piggy_back :user_name, :from => _association_, :attributes => _attribute list_
    #
    # or
    #
    #    piggy_back :user_name, _association_, _attr_1_, ...
    #
    def piggy_back(piggy_back_name, *args)
      if args.first.is_a? Hash
        hash = args.first
        attributes = hash[:attributes]
        reflection_name = hash[:from]
      else
        reflection_name = args.first
        attributes = args[1..-1]
      end
      reflection = reflections[reflection_name]
      unless [:belongs_to, :has_one].include? reflection.macro
        raise "can't piggy back #{reflection.macro} on class #{self}"
      end
      
      if attributes.empty?
        columns = reflection.klass.content_columns
        attributes = [:*]
      else
        columns = attributes.map{|name| reflection.klass.columns_hash[name.to_s]}
      end
      columns.each{|column| define_piggy_back_read_method(column, reflection)}
      
      add_piggy_back_selects_and_joins!(reflection_name, attributes, select="", joins="")
      piggy_back_info[piggy_back_name] = [select, joins]
    end
           
    # replace piggy option by adding to :select and :joins options
    def add_piggy_back!(options)
      piggy = options.delete(:piggy) or return
      select = (options[:select] ||= "#{table_name}.*")
      joins = (options[:joins] ||= '')
      piggy = [piggy] if piggy.is_a? Symbol
      piggy_info_hash = piggy_back_info()
      for piggy_name in piggy do
        p_info = piggy_info_hash[piggy_name]
        select << p_info[0]
        joins << p_info[1]
      end
    end
    
    protected
    def piggy_back_info
      @piggy_back_info ||= descends_from_active_record? ? {} : superclass.piggy_back_info
    end
    
    # define reader method(s) for piggy backed association attribute
    def define_piggy_back_read_method(column, reflection)
      attr = column.name
      attr_key = "#{reflection.name}_#{attr}"
      return if instance_methods.include?(attr_key)
      
      cast_code = column.type_cast_code('v')
      access_code = if cast_code
                      "(v=@attributes['#{attr_key}']) && #{cast_code}"
                    else
                      "@attributes['#{attr_key}']"
                    end
      
      self.class_eval <<-"end_method"
        def #{attr_key}
          if @attributes.has_key? '#{attr_key}'
            #{access_code}
          else
            #{reflection.name}.#{attr}
          end
        end
      end_method
    end
    
    # add select and join for piggy backed +atrributes+ to +select+ and +join+ for a given +reflection+.
    def add_piggy_back_selects_and_joins!(reflection_name, attributes, select, joins)
      ktn = table_name
      kpkey = primary_key
      reflection = reflections[reflection_name]          
      atn = reflection.table_name
      attributes.each do |attr|
        select << ", #{atn}.#{attr} AS #{reflection.name}_#{attr}"
      end
      fkey = reflection.primary_key_name
      case reflection.macro
      when :belongs_to
        joins << " LEFT JOIN #{atn} ON #{atn}.#{kpkey}=#{ktn}.#{fkey} "
      when :has_one
        joins << " LEFT JOIN #{atn} ON #{atn}.#{fkey}=#{ktn}.#{kpkey} "
      else
        raise "can't piggy back #{reflection.macro} on class #{klass}"
      end
    end
  
  end
end

module ActionController::Pagination
  
  # make paginator swallow piggy option
  DEFAULT_OPTIONS[:piggy] = nil
  
  # pass piggy option to model find
  def find_collection_for_pagination(model, options, paginator)
    model.find(:all,
               :conditions => options[:conditions],
               :order => options[:order_by] || options[:order],
               :joins => options[:join] || options[:joins],
               :include => options[:include],
               :select => options[:select],
               :limit => options[:per_page],
               :offset => paginator.current.offset,
               :piggy => options[:piggy])
  end
  
end
