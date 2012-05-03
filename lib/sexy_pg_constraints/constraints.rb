module SexyPgConstraints
  module Constraints
    module_function

    ##
    # Only allow listed values.
    #
    # Example:
    #   constrain :books, :variation, :whitelist => %w(hardcover softcover)
    #
    def whitelist(table, column, options)
      "check (#{table}.#{column} in (#{ options.collect{|v| "'#{v}'"}.join(',')  }))"
    end

    ##
    # Prohibit listed values.
    #
    # Example:
    #   constrain :books, :isbn, :blacklist => %w(invalid_isbn1 invalid_isbn2)
    #
    def blacklist(table, column, options)
      "check (#{table}.#{column} not in (#{ options.collect{|v| "'#{v}'"}.join(',') }))"
    end

    ##
    # The value must have at least 1 non-space character.
    #
    # Example:
    #   constrain :books, :title, :not_blank => true
    #
    def not_blank(table, column, options)
      "check ( length(btrim(#{table}.#{column})) > 0 )"
    end
    alias_method :present, :not_blank
    module_function :present

    ##
    # The value must have characters other than those listed in the option string.
    #
    # Example:
    #   constrain :books, :title, :not_only => 'abcd'
    #
    def not_only(table, column, options)
      "check ( length(btrim(#{table}.#{column}, E'#{options}')) > 0 )"
    end

    ##
    # The value must not have leading or trailing spaces.
    #
    # You can pass a string as an option to indicate what characters are trimmed.
    #
    # Example:
    #   constrain :books, :title, :trimmed => true
    #   constrain :books, :title, :trimmed => "abc"
    #
    def trimmed(table, column, options)
      if options == true
        "check (length(#{table}.#{column}) = length(btrim(#{table}.#{column})))"
      else
        "check (length(#{table}.#{column}) = length(btrim(#{table}.#{column}, E'#{options}')))"
      end
    end
    alias_method :stripped, :trimmed
    module_function :stripped

    ##
    # The numeric value must be within given range.
    #
    # Example:
    #   constrain :books, :year, :within => 1980..2008
    #   constrain :books, :year, :within => 1980...2009
    #   constrain :books, :year, :within => {:range => 1979..2008, :exclude_beginning => true}
    #   constrain :books, :year, :within => {:range => 1979..2009, :exclude_beginning => true, :exclude_end => true}
    # (the four lines above do the same thing)
    #
    def within(table, column, options)
      column_ref = column.to_s.include?('.') ? column : "#{table}.#{column}"
      if options.respond_to?(:to_hash)
        options = options.to_hash
        options.assert_valid_keys(:range, :exclude_end, :exclude_beginning)
        range = options.fetch(:range)
        exclude_end = options.has_key?(:exclude_end) ? options.fetch(:exclude_end) : range.exclude_end?
        exclude_beginning = options.has_key?(:exclude_beginning) ? options.fetch(:exclude_beginning) : false
      else
        range = options
        exclude_end = range.exclude_end?
        exclude_beginning = false
      end
      "check (#{column_ref} >#{'=' unless exclude_beginning} #{range.begin} and #{column_ref} <#{'=' unless exclude_end} #{range.end})"
    end

    ##
    # Check the length of strings/text to be within the range.
    #
    # Example:
    #   constrain :books, :author, :length_within => 4..50
    #
    def length_within(table, column, options)
      within(table, "length(#{table}.#{column})", options)
    end

    ##
    # Allow only valid email format.
    #
    # Example:
    #   constrain :books, :author, :email => true
    #
    def email(table, column, options)
      "check (((#{table}.#{column})::text ~ E'^([-a-z0-9]+)@([-a-z0-9]+[.]+[a-z]{2,4})$'::text))"
    end

    ##
    # Allow only alphanumeric values.
    #
    # Example:
    #   constrain :books, :author, :alphanumeric => true
    #
    def alphanumeric(table, column, options)
      "check (((#{table}.#{column})::text ~* '^[a-z0-9]+$'::text))"
    end

    ##
    # Allow only lower case values.
    #
    # Example:
    #   constrain :books, :author, :lowercase => true
    #
    def lowercase(table, column, options)
      "check (#{table}.#{column} = lower(#{table}.#{column}))"
    end

    ##
    # Allow only positive values.
    #
    # Example:
    #   constrain :books, :quantity, :positive => true
    #
    def positive(table, column, options)
      greater_than_or_equal_to(table, column, 0)
    end

    ##
    # Allow only values less than the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than => 12
    #
    def less_than(table, column, options)
      "check (#{table}.#{column} < #{options})"
    end

    ##
    # Allow only values less than or equal to the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than => 12
    #
    def less_than_or_equal_to(table, column, options)
      "check (#{table}.#{column} <= #{options})"
    end

    ##
    # Allow only values greater than the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than => 12
    #
    def greater_than(table, column, options)
      "check (#{table}.#{column} > #{options})"
    end

    ##
    # Allow only values greater than or equal to the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than_or_equal_to => 12
    #
    def greater_than_or_equal_to(table, column, options)
      "check (#{table}.#{column} >= #{options})"
    end

    ##
    # Allow only odd values.
    #
    # Example:
    #   constrain :books, :quantity, :odd => true
    #
    def odd(table, column, options)
      "check (mod(#{table}.#{column}, 2) != 0)"
    end

    ##
    # Allow only even values.
    #
    # Example:
    #   constrain :books, :quantity, :even => true
    #
    def even(table, column, options)
      "check (mod(#{table}.#{column}, 2) = 0)"
    end

    ##
    # Make sure every entry in the column is unique.
    #
    # Example:
    #   constrain :books, :isbn, :unique => true
    #
    def unique(table, column, options)
      column = Array(column).map {|c| %{"#{c}"} }.join(', ')
      "unique (#{column})"
    end

    ##
    # Allow only one of the values in the given columns to be true.
    # Only reasonable with more than one column.
    # See Enterprise Rails, Chapter 10 for details.
    #
    # Example:
    #   constrain :books, [], :xor => true
    #
    def xor(table, column, options)
      addition = Array(column).map {|c| %{("#{c}" is not null)::integer} }.join(' + ')

      "check (#{addition} = 1)"
    end

    ##
    # Allow only text/strings of the exact length specified, no more, no less.
    #
    # Example:
    #   constrain :books, :hash, :exact_length => 32
    #
    def exact_length(table, column, options)
      "check ( length(trim(both from #{table}.#{column})) = #{options} )"
    end

    ##
    # Allow only values that match the regular expression.
    #
    # Example:
    #   constrain :orders, :visa, :format => /^([4]{1})([0-9]{12,15})$/
    #
    def format(table, column, options)
      "check (((#{table}.#{column})::text #{options.casefold? ? '~*' : '~'}  E'#{options.source}'::text ))"
    end

    ##
    # Add foreign key constraint.
    #
    # Example:
    #   constrain :books, :author_id, :reference => {:authors => :id, :on_delete => :cascade}
    #
    def reference(table, column, options)
      on_delete = options.delete(:on_delete)
      fk_table = options.keys.first
      fk_column = options[fk_table]

      on_delete = "on delete #{on_delete}" if on_delete

      %{foreign key ("#{column}") references #{fk_table} (#{fk_column}) #{on_delete}}
    end
  end
end
