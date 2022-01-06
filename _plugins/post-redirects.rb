module Jekyll

  # See <http://www.marran.com/tech/creating-redirects-with-jekyll/>.

  # The redirect page creates a simple page that refreshes a user from a URL alias to an existing post.
  # Redirects are only generated if there is a "redirects" parameters in _config.yml.

  class Redirects < Generator

    safe true
    priority :low

    # Check config file.
    def generate(site)
      generate_redirects(site) if (site.config['redirects'])
    end

    # Find posts and create redirect pages.
    def generate_redirects(site)
      site.posts.docs.select{|post| post.data.key? 'redirects' }.each do |post|
        post.data['redirects'].each do |redirect|
          redirect = RedirectPage.new(site, site.source, redirect, post.id)
          redirect.render(site.layouts, site.site_payload)
          redirect.write(site.dest)
          site.pages << redirect
        end
      end
    end

  end

  class RedirectPage < Page

    def initialize(site, base, path, destination)

      @site = site
      @base = base
      @dir = path
      @name = 'index.html'
      self.process(@name)

      self.read_yaml(File.join(base, '_layouts'), 'redirect.html')
      self.data['source_url'] = destination

    end

  end

end
