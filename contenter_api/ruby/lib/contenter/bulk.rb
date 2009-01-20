module Contenter
  # Represents bulk content.
  class Bulk
    def initialize hash = nil
      hash ||= { }
      @hash = hash
      @hash[:api_version] ||= 1
      @hash[:error] ||= nil
      @hash[:result_columns] ||=
        [
         :id,
         :uuid,
         :content_type,
         :content_key,
         :language,
         :country,
         :brand,
         :application,
         :mime_type,
         :data,
        ]
    end


    def results
      @hash[:results]
    end


    def render_csv fh = nil
      raise Exception, "not implemented"
    end


    # Renders.
    def render_yaml fh = nil
      fh ||= StringIO.new

      document = @hash
      cols = document[:result_columns]
      fh.puts <<"END"
# THIS IS UTF-8 YAML: CHECK YOUR EDITOR SETTINGS BEFORE EDITING IT!
# GENERATED BY Contenter::Bulk#render_yaml
--- 
:api_version: #{document[:api_version]}
END
      if x = document[:error]
        fh.puts ":error: #{x.inspect.inspect}" 
      end

      if document[:results]
        document[:result_count] = document[:results].size
      fh.puts <<"END"
:result_count: #{document[:result_count]}
:result_columns: #{document[:result_columns].inspect}
:results: 
END
      document[:results].each do | r |
        case r
        when Hash
          r = cols.map { | c | r[c] }
        when Array
          #
        when ActiveRecord::Base
          r = cols.map { | c | r.send(c) }
        else
          raise ArgumentError
        end
        
        cols.each_with_index do | c, i |
          v = r[i]
          fh.write "#{i == 0 ? '-' : ' '} - "

          case c
          when :data
            if (v =~ /\n/)
              fh.puts <<"END"
|
    #{v.gsub(/(\r?\n)/){|x| x + "    "}}
END
            else
              fh.puts <<"END"
"#{v.gsub(/([\\\"])/){|x| '\\' + x }}"
END
            end
          else
            fh.puts "#{v.inspect}"
          end
        end
      end
      end

      fh
    end
  end # class
end # module

