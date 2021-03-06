require "./config"
require "./exception"

module Crystal
  struct CrystalPath
    class Error < LocationlessException
    end

    def self.default_path
      ENV["CRYSTAL_PATH"]? || Crystal::Config.path
    end

    @crystal_path : Array(String)

    def initialize(path = CrystalPath.default_path, codegen_target = Config.host_target)
      @crystal_path = path.split(Process::PATH_DELIMITER).reject &.empty?
      add_target_path(codegen_target)
    end

    private def add_target_path(codegen_target)
      target = "#{codegen_target.architecture}-#{codegen_target.os_name}"

      @crystal_path.each do |path|
        path = File.join(path, "lib_c", target)
        if Dir.exists?(path)
          @crystal_path << path unless @crystal_path.includes?(path)
          return
        end
      end
    end

    def find(filename, relative_to = nil) : Array(String)?
      relative_to = File.dirname(relative_to) if relative_to.is_a?(String)

      if filename.starts_with? '.'
        result = find_in_path_relative_to_dir(filename, relative_to)
      else
        result = find_in_crystal_path(filename)
      end

      cant_find_file filename, relative_to unless result

      result = [result] if result.is_a?(String)
      result
    end

    private def find_in_path_relative_to_dir(filename, relative_to)
      return unless relative_to.is_a?(String)

      # Check if it's a wildcard.
      if filename.ends_with?("/*") || (recursive = filename.ends_with?("/**"))
        filename_dir_index = filename.rindex('/').not_nil!
        filename_dir = filename[0..filename_dir_index]
        relative_dir = "#{relative_to}/#{filename_dir}"
        if File.exists?(relative_dir)
          files = [] of String
          gather_dir_files(relative_dir, files, recursive)
          return files
        end

        return nil
      end

      relative_filename = "#{relative_to}/#{filename}"

      # Check if .cr file exists.
      relative_filename_cr = relative_filename.ends_with?(".cr") ? relative_filename : "#{relative_filename}.cr"
      if File.exists?(relative_filename_cr)
        return File.expand_path(relative_filename_cr)
      end

      filename_is_relative = filename.starts_with?('.')

      if !filename_is_relative && (slash_index = filename.index('/'))
        # If it's "foo/bar/baz", check if "foo/src/bar/baz.cr" exists (for a shard, non-namespaced structure)
        before_slash, after_slash = filename.split('/', 2)

        absolute_filename = File.expand_path("#{relative_to}/#{before_slash}/src/#{after_slash}.cr")
        return absolute_filename if File.exists?(absolute_filename)

        # Then check if "foo/src/foo/bar/baz.cr" exists (for a shard, namespaced structure)
        absolute_filename = File.expand_path("#{relative_to}/#{before_slash}/src/#{before_slash}/#{after_slash}.cr")
        return absolute_filename if File.exists?(absolute_filename)

        # If it's "foo/bar/baz", check if "foo/bar/baz/baz.cr" exists (std, nested)
        basename = File.basename(relative_filename)
        absolute_filename = File.expand_path("#{relative_to}/#{filename}/#{basename}.cr")
        return absolute_filename if File.exists?(absolute_filename)

        # If it's "foo/bar/baz", check if "foo/src/foo/bar/baz/baz.cr" exists (shard, non-namespaced, nested)
        absolute_filename = File.expand_path("#{relative_to}/#{before_slash}/src/#{after_slash}/#{after_slash}.cr")
        return absolute_filename if File.exists?(absolute_filename)

        # If it's "foo/bar/baz", check if "foo/src/foo/bar/baz/baz.cr" exists (shard, namespaced, nested)
        absolute_filename = File.expand_path("#{relative_to}/#{before_slash}/src/#{before_slash}/#{after_slash}/#{after_slash}.cr")
        return absolute_filename if File.exists?(absolute_filename)

        return nil
      end

      basename = File.basename(relative_filename)

      # If it's "foo", check if "foo/foo.cr" exists (for the std, nested)
      absolute_filename = File.expand_path("#{relative_filename}/#{basename}.cr")
      return absolute_filename if File.exists?(absolute_filename)

      unless filename_is_relative
        # If it's "foo", check if "foo/src/foo.cr" exists (for a shard)
        absolute_filename = File.expand_path("#{relative_filename}/src/#{basename}.cr")
        return absolute_filename if File.exists?(absolute_filename)
      end

      nil
    end

    private def gather_dir_files(dir, files_accumulator, recursive)
      files = [] of String
      dirs = [] of String

      Dir.each_child(dir) do |filename|
        full_name = "#{dir}/#{filename}"

        if File.directory?(full_name)
          if recursive
            dirs << filename
          end
        else
          if filename.ends_with?(".cr")
            files << full_name
          end
        end
      end

      files.sort!
      dirs.sort!

      files.each do |file|
        files_accumulator << File.expand_path(file)
      end

      dirs.each do |subdir|
        gather_dir_files("#{dir}/#{subdir}", files_accumulator, recursive)
      end
    end

    private def find_in_crystal_path(filename)
      @crystal_path.each do |path|
        required = find_in_path_relative_to_dir(filename, path)
        return required if required
      end

      nil
    end

    private def cant_find_file(filename, relative_to)
      error = "can't find file '#{filename}'"

      if filename.starts_with? '.'
        error += " relative to '#{relative_to}'" if relative_to
      else
        error = <<-NOTE
          #{error}

          If you're trying to require a shard:
          - Did you remember to run `shards install`?
          - Did you make sure you're running the compiler in the same directory as your shard.yml?
          NOTE
      end

      raise Error.new(error)
    end
  end
end
