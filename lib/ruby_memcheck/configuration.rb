# frozen_string_literal: true

module RubyMemcheck
  class Configuration
    DEFAULT_VALGRIND = "valgrind"
    DEFAULT_VALGRIND_OPTIONS = [
      "--num-callers=50",
      "--error-limit=no",
      "--undef-value-errors=no",
      "--leak-check=full",
      "--show-leak-kinds=definite",
    ].freeze
    DEFAULT_VALGRIND_SUPPRESSIONS_DIR = "suppressions"
    DEFAULT_SKIPPED_RUBY_FUNCTIONS = [
      /\Arb_check_funcall/,
      /\Arb_enc_raise\z/,
      /\Arb_exc_raise\z/,
      /\Arb_funcall/,
      /\Arb_intern/,
      /\Arb_ivar_set\z/,
      /\Arb_raise\z/,
      /\Arb_rescue/,
      /\Arb_respond_to\z/,
      /\Arb_yield/,
    ].freeze

    attr_reader :binary_name, :ruby, :valgrind_options, :valgrind,
      :skipped_ruby_functions, :valgrind_xml_file, :output_io

    def initialize(
      binary_name:,
      ruby: FileUtils::RUBY,
      valgrind: DEFAULT_VALGRIND,
      valgrind_options: DEFAULT_VALGRIND_OPTIONS,
      valgrind_suppressions_dir: DEFAULT_VALGRIND_SUPPRESSIONS_DIR,
      skipped_ruby_functions: DEFAULT_SKIPPED_RUBY_FUNCTIONS,
      valgrind_xml_file: Tempfile.new,
      output_io: $stderr
    )
      @binary_name = binary_name
      @ruby = ruby
      @valgrind = valgrind
      @valgrind_options =
        valgrind_options +
        get_valgrind_suppression_files(valgrind_suppressions_dir).map { |f| "--suppressions=#{f}" }
      @skipped_ruby_functions = skipped_ruby_functions
      @output_io = output_io

      if valgrind_xml_file
        @valgrind_xml_file = valgrind_xml_file
        @valgrind_options += [
          "--xml=yes",
          "--xml-file=#{valgrind_xml_file.path}",
        ]
      end
    end

    def command(*args)
      "#{valgrind} #{valgrind_options.join(" ")} #{ruby} #{args.join(" ")}"
    end

    def skip_stack?(stack)
      in_binary = false

      stack.frames.each do |frame|
        fn = frame.fn

        if frame_in_ruby?(frame) # in ruby
          unless in_binary
            # Skip this stack because it was called from Ruby
            return true if skipped_ruby_functions.any? { |r| r.match?(fn) }
          end
        elsif frame_in_binary?(frame) # in binary
          in_binary = true

          # Skip the Init function
          return true if fn == "Init_#{binary_name}"
        end
      end

      !in_binary
    end

    def frame_in_ruby?(frame)
      frame.obj == ruby ||
        # Hack to fix Ruby built with --enabled-shared
        File.basename(frame.obj) == "libruby.so.#{RUBY_VERSION}"
    end

    def frame_in_binary?(frame)
      if frame.obj
        File.basename(frame.obj, ".*") == binary_name
      else
        false
      end
    end

    private

    def get_valgrind_suppression_files(dir)
      full_ruby_version = "#{RUBY_ENGINE}-#{RUBY_VERSION}.#{RUBY_PATCHLEVEL}"
      versions = [full_ruby_version]
      (0..3).reverse_each { |i| versions << full_ruby_version.split(".")[0, i].join(".") }
      versions << RUBY_ENGINE

      versions.map do |version|
        Dir[File.join(dir, "#{binary_name}_#{version}.supp")]
      end.flatten
    end
  end
end
