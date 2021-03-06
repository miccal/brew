# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpec
      # Checks that spec file paths are consistent and well-formed.
      #
      # By default, this checks that spec file paths are consistent with the
      # test subject and and enforces that it reflects the described
      # class/module and its optionally called out method.
      #
      # With the configuration option `IgnoreMethods` the called out method will
      # be ignored when determining the enforced path.
      #
      # With the configuration option `CustomTransform` modules or classes can
      # be specified that should not as usual be transformed from CamelCase to
      # snake_case (e.g. 'RuboCop' => 'rubocop' ).
      #
      # With the configuration option `SpecSuffixOnly` test files will only
      # be checked to ensure they end in '_spec.rb'. This option disables
      # checking for consistency in the test subject or test methods.
      #
      # @example
      #   # bad
      #   whatever_spec.rb         # describe MyClass
      #
      #   # bad
      #   my_class_spec.rb         # describe MyClass, '#method'
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_method_spec.rb  # describe MyClass, '#method'
      #
      #   # good
      #   my_class/method_spec.rb  # describe MyClass, '#method'
      #
      # @example when configuration is `IgnoreMethods: true`
      #   # bad
      #   whatever_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass, '#method'
      #
      # @example when configuration is `SpecSuffixOnly: true`
      #   # good
      #   whatever_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass
      #
      #   # good
      #   my_class_spec.rb         # describe MyClass, '#method'
      #
      class FilePath < Base
        include TopLevelGroup

        MSG = 'Spec path should end with `%<suffix>s`.'

        def_node_matcher :const_described, <<~PATTERN
          (block
            $(send #rspec? _example_group $(const ...) $...) ...
          )
        PATTERN

        def_node_search :routing_metadata?, '(pair (sym :type) (sym :routing))'

        def on_top_level_example_group(node)
          return unless top_level_groups.one?

          const_described(node) do |send_node, described_class, arguments|
            next if routing_spec?(arguments)

            ensure_correct_file_path(send_node, described_class, arguments)
          end
        end

        private

        def ensure_correct_file_path(send_node, described_class, arguments)
          pattern = pattern_for(described_class, arguments.first)
          return if filename_ends_with?(pattern)

          # For the suffix shown in the offense message, modify the regular
          # expression pattern to resemble a glob pattern for clearer error
          # messages.
          offense_suffix = pattern.gsub('.*', '*').sub('[^/]', '')
            .sub('\.', '.')
          add_offense(send_node, message: format(MSG, suffix: offense_suffix))
        end

        def routing_spec?(args)
          args.any?(&method(:routing_metadata?))
        end

        def pattern_for(described_class, method_name)
          return pattern_for_spec_suffix_only? if spec_suffix_only?

          [
            expected_path(described_class),
            name_pattern(method_name),
            '[^/]*_spec\.rb'
          ].join
        end

        def pattern_for_spec_suffix_only?
          '.*_spec\.rb'
        end

        def name_pattern(method_name)
          return unless method_name&.str_type?

          ".*#{method_name.str_content.gsub(/\W/, '')}" unless ignore_methods?
        end

        def expected_path(constant)
          File.join(
            constant.const_name.split('::').map do |name|
              custom_transform.fetch(name) { camel_to_snake_case(name) }
            end
          )
        end

        def camel_to_snake_case(string)
          string
            .gsub(/([^A-Z])([A-Z]+)/, '\1_\2')
            .gsub(/([A-Z])([A-Z][^A-Z\d]+)/, '\1_\2')
            .downcase
        end

        def custom_transform
          cop_config.fetch('CustomTransform', {})
        end

        def ignore_methods?
          cop_config['IgnoreMethods']
        end

        def filename_ends_with?(pattern)
          filename = File.expand_path(processed_source.buffer.name)
          filename.match?("#{pattern}$")
        end

        def relevant_rubocop_rspec_file?(_file)
          true
        end

        def spec_suffix_only?
          cop_config['SpecSuffixOnly']
        end
      end
    end
  end
end
