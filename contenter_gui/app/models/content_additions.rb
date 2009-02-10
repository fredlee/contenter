module ContentAdditions
  def streamlined_name *args
    content_key.code
  end

  def data_short max_size = 16
    x = data || ''
    x =~ /\A[\n\r]*([^\n\r]*)[\n\r]/
    x = $1 || x
    if x != data || data.size > max_size
      # Handle UTF-8: do not truncate in the middle of a UTF-8 sequence.
      while max_size < data.size && (c = x[max_size]) && c > 127
        max_size += 1
      end

      x = x[0 .. max_size] + '...'
    end
    x
  end

  def data_formatted
    "<pre>#{ERB::Util.h(data || '')}</pre>"
  end

  def data_text_lines
    (x = data) ? x.count("\n") : 0
  end

  def data_text
    data
  end

  def data_text= x
    self.data = x
  end
end