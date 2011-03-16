# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{hudson_deployer}
  s.version = "0.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Collin VanDyck"]
  s.date = %q{2011-03-16}
  s.description = %q{Unmagical Capistrano deployment using Hudson}
  s.email = %q{collinvandyck @nospam@ gmail.com}
  s.extra_rdoc_files = ["LICENSE", "README.md", "lib/hudson_deployer.rb"]
  s.files = ["LICENSE", "Manifest", "README.md", "Rakefile", "lib/hudson_deployer.rb", "hudson_deployer.gemspec"]
  s.homepage = %q{https://github.com/collinvandyck/hudson_deployer}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Hudson_deployer", "--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{hudson_deployer}
  s.rubygems_version = %q{1.5.2}
  s.summary = %q{Unmagical Capistrano deployment using Hudson}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
