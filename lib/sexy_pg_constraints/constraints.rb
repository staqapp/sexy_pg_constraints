module SexyPgConstraints
  module Constraints
    module_function

    ##
    # Only allow listed values.
    #
    # Example:
    #   constrain :books, :variation, :whitelist => %w(hardcover softcover)
    #
    def whitelist(column, options)
      %{check ("#{column}" in (#{ options.collect{|v| "'#{v}'"}.join(',')  }))}
    end

    ##
    # Prohibit listed values.
    #
    # Example:
    #   constrain :books, :isbn, :blacklist => %w(invalid_isbn1 invalid_isbn2)
    #
    def blacklist(column, options)
      %{check ("#{column}" not in (#{ options.collect{|v| "'#{v}'"}.join(',') }))}
    end

    ##
    # The value must have at least 1 non-space character.
    #
    # Example:
    #   constrain :books, :title, :present => true
    #
    def present(column, options)
      %{check ( length(btrim("#{column}")) > 0 )}
    end

    ##
    # The value must have characters other than those listed in the option string.
    #
    # Example:
    #   constrain :books, :title, :not_only => 'abcd'
    #
    def not_only(column, options)
      %{check ( length(btrim("#{column}", E'#{options}')) > 0 )}
    end

    ##
    # The value must not have leading or trailing spaces.
    #
    # You can pass a string as an option to indicate what characters are stripped.
    #
    # Example:
    #   constrain :books, :title, :stripped => true
    #   constrain :books, :title, :stripped => "abc"
    #
    def stripped(column, options)
      if options == true
        %{check (length("#{column}") = length(btrim("#{column}")))}
      else
        %{check (length("#{column}") = length(btrim("#{column}", E'#{options}')))}
      end
    end

    ##
    # The numeric value must be within given range.
    #
    # Example:
    #   constrain :books, :year, :within => 1980..2008
    #   constrain :books, :year, :within => 1980...2009
    # (the two lines above do the same thing)
    #
    def within(column, range)
      column_ref = column.to_s.include?('"') ? column : %{"#{column}"}
      "check (#{column_ref} >= #{range.begin} and #{column_ref} <#{'=' unless range.exclude_end?} #{range.end})"
    end

    ##
    # Check the length of strings/text to be within the range.
    #
    # Example:
    #   constrain :books, :author, :length_within => 4..50
    #
    def length_within(column, options)
      within(%{length("#{column}")}, options)
    end

    ##
    # Allow only valid email format.
    #
    # Example:
    #   constrain :books, :author, :email => true
    #
    def email(column, options)
      %{check ((("#{column}")::text ~ E'^([-a-z0-9]+)@([-a-z0-9]+[.]+[a-z]{2,4})$'::text))}
    end

    ##
    # Allow only alphanumeric values.
    #
    # Example:
    #   constrain :books, :author, :alphanumeric => true
    #
    def alphanumeric(column, options)
      %{check ((("#{column}")::text ~* '^[a-z0-9]+$'::text))}
    end

    ##
    # Allow only lower case values.
    #
    # Example:
    #   constrain :books, :author, :lowercase => true
    #
    def lowercase(column, options)
      %{check ("#{column}" = lower("#{column}"))}
    end

    ##
    # Allow only positive values.
    #
    # Example:
    #   constrain :books, :quantity, :positive => true
    #
    def positive(column, options)
      greater_than_or_equal_to(column, 0)
    end

    ##
    # Allow only values less than the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :less_than => 12
    #
    def less_than(column, options)
      %{check ("#{column}" < #{options})}
    end

    ##
    # Allow only values less than or equal to the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :less_than_or_equal_to => 12
    #
    def less_than_or_equal_to(column, options)
      %{check ("#{column}" <= #{options})}
    end

    ##
    # Allow only values greater than the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than => 12
    #
    def greater_than(column, options)
      %{check ("#{column}" > #{options})}
    end

    ##
    # Allow only values greater than or equal to the provided limit.
    #
    # Example:
    #   constrain :books, :quantity, :greater_than_or_equal_to => 12
    #
    def greater_than_or_equal_to(column, options)
      %{check ("#{column}" >= #{options})}
    end

    ##
    # Allow only odd values.
    #
    # Example:
    #   constrain :books, :quantity, :odd => true
    #
    def odd(column, options)
      %{check (mod("#{column}", 2) != 0)}
    end

    ##
    # Allow only even values.
    #
    # Example:
    #   constrain :books, :quantity, :even => true
    #
    def even(column, options)
      %{check (mod("#{column}", 2) = 0)}
    end

    ##
    # Make sure every entry in the column is unique.
    #
    # Example:
    #   constrain :books, :isbn, :unique => true
    #
    def unique(column, options)
      columns = Array(column).map {|c| %{"#{c}"} }.join(', ')
      "unique(#{columns})"
    end

    ##
    # Allow only one of the values in the given columns to be true.
    # Only reasonable with more than one column.
    # See Enterprise Rails, Chapter 10 for details.
    #
    # Example:
    #   constrain :books, [], :xor => true
    #
    def xor(column, options)
      addition = Array(column).map {|c| %{("#{c}" is not null)::integer} }.join(' + ')

      "check (#{addition} = 1)"
    end

    ##
    # Allow only text/strings of the exact length specified, no more, no less.
    #
    # Example:
    #   constrain :books, :hash, :exact_length => 32
    #
    def exact_length(column, options)
      %{check ( length(trim(both from "#{column}")) = #{options} )}
    end

    ##
    # Allow only values that match the regular expression.
    #
    # Example:
    #   constrain :orders, :visa, :format => /^([4]{1})([0-9]{12,15})$/
    #
    def format(column, options)
      %{check ((("#{column}")::text #{options.casefold? ? '~*' : '~'}  E'#{options.source}'::text ))}
    end

    ##
    # Add foreign key constraint.
    #
    # Example:
    #   constrain :books, :author_id, :reference => {:authors => :id, :on_delete => :cascade}
    #
    def reference(column, options)
      on_delete = options.delete(:on_delete)
      fk_table = options.keys.first
      fk_column = options[fk_table]

      on_delete = "on delete #{on_delete}" if on_delete

      %{foreign key ("#{column}") references #{fk_table} (#{fk_column}) #{on_delete}}
    end
  end
end
