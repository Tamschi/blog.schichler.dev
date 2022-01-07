# Just the require here breaks the redirect generator.
# require "link_preview"

Jekyll::Hooks.register :posts, :pre_render do |document|
  def dbg!(x)
    $stderr.puts(x.inspect)
  end

  document.content.gsub!(/^\n%\[(.*)\]\n$/) do |match|
    replace = $&
    url = $1

    link = "\n<#{url}>\n"

    $stderr.puts("Warning: Replacing rich preview `%[#{url}]` in #{document.path} with plain link `<#{url}>`.")

    link
  end

end
