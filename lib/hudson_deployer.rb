require 'capistrano'
require 'rest_client'
require 'json'
require 'erb'

class Deploy
  attr_accessor :application,
                :user,
                :build_num,
                :artifact_url
                
  def initialize(&block)
    if block_given?
      yield self
    end
  end
  
  def debug
    puts "Deployment Configuration:"
    [:application, :user, :build_num].each do |f|
      puts "  #{f}: #{send(f)}"
    end
  end
  
end

Capistrano::Configuration.instance(:must_exist).load do

  def _cset(name, *args, &block)
    unless exists?(name)
      set(name, *args, &block)
    end
  end

  def hud_api(url)
    JSON.parse(RestClient.get(url + "/api/json"))
  end

  # environment configuration
  ######################################################################

  # by default we are in the staging environment
  @env = :staging
  
  task :staging do
    @env = :staging
  end
  
  task :production do
    @env = :production
  end
  
  set(:config) do
    {
      :default => {},
      :staging => {},
      :production => {}
    }
  end
  
  def config_h
    config[:default].merge(config[@env])
  end

  # required variables
  ######################################################################

  _cset(:hudson) { abort ":hudson must be set (e.g. build.yammer.com)" }
  _cset(:application) { abort ":application must be set" }
  _cset(:build) { abort ":build must be set (e.g. app-release)" }
  _cset(:user) { abort ":user must be set" }
  _cset(:launch_command) { abort ":launch_command must be set" }

  # derived variables
  ######################################################################

  set(:directory) { "/opt/#{application}" }
  
  set(:current_release) { "#{directory}/releases/#{Time.now.to_i}" }

  set(:job) do
    record = hud_api(hudson)["jobs"].find { |j| j["name"] == build }
    abort("No such hudson build could be found") if !record
    hud_api(record["url"])
  end

  set(:current_build) do
    builds = job["builds"]
    abort("There are no existing builds for this project") if builds.empty?
    url = builds.first["url"]
    hud_api(url).tap do |b|
      if b["result"] != "SUCCESS"
        abort("The last build was not successful: #{b["result"]}")
      end
      if b["building"] == true
        abort("Project is currently building. You must wait until it finishes.")
      end
    end
  end

  set(:artifact_url) do
    artifacts = current_build["artifacts"]
    if artifacts.empty?
      abort("No artifacts exist for this project!")
    end
    artifact = if artifacts.length > 1
      puts "More than one artifact was found. Please choose:"
      artifacts.each_with_index do |artifact, index|
        puts "#{index}: #{artifact["relativePath"]}"
      end
      print  "? "
      artifact_index = Capistrano::CLI.ui.ask("choice: ").to_i
      artifacts[artifact_index]
    else
      artifacts.first
    end
    current_build["url"] + "artifact/" + artifact["relativePath"]
  end

  set(:artifact_filename) do
    artifact_url.split("/").last
  end
  
  set(:tmpdir) do
    "/tmp/deployer-#{Time.now.to_i}".tap do |tmp|
      FileUtils.mkdir_p(tmp)
    end
  end
  
  set(:local_entries) do
    Dir.entries(File.expand_path(Dir.pwd)).reject do |name|
      name =~ /^\./ || name == "Capfile"
    end
  end
  
  set(:template_names) do
    Dir.entries(File.expand_path(Dir.pwd + "/templates")).reject do |name|
      name =~ /^\./
    end
  end
  
  def build_deployment
    Deploy.new do |d|
      d.application = application
      d.user = user
      d.build_num = current_build["number"]
      d.artifact_url = artifact_url
    end
  end

  def make_release_directory
    run "#{sudo} mkdir -p #{current_release}", :roles => "app"
    run "#{sudo} chown -R #{deployer} #{current_release}", :roles => "app"
  end
  
  def create_local_build
    from = File.expand_path(Dir.pwd + "/" + application)
    local_entries.each { |f| FileUtils.cp_r f, tmpdir, :verbose => true }
  end
  
  def verify_plan
    puts "*" * 80
    puts "Deployment plan:"
    @deploy.debug
    puts "Copying assets:"
    puts `find #{tmpdir}`
    puts "*" * 80
    unless Capistrano::CLI.ui.ask("Is this what you want?") =~ /^y.*/i
      exit
    end
  end

  def download_artifact
    puts "Downloading artifact..."
    `wget #{@deploy.artifact_url} -O #{tmpdir}/#{artifact_filename}`
  end
  
  def execute_actions
    @rendered_actions.each do |action|
      run "cd #{current_release} && sh #{action}"
    end
  end
  
  def transfer_build
    puts "Transferring build..."
    Dir.entries(tmpdir).each do |e|
      unless e =~ /^\./
        tmpfile = "/tmp/#{Time.now.to_i}"
        upload "#{tmpdir}/#{e}", tmpfile
        run "#{sudo} mv #{tmpfile} #{current_release}/#{e}"
        run "#{sudo} chown -R #{deployer}:#{deployer} #{current_release}/#{e}"
      end
    end
  end
  
  def symlink
    link = "#{current_release}/../current"
    run "#{sudo} rm #{link} || true"
    run "#{sudo} ln -sF #{current_release} #{link}"
  end
  
  def cleanup
    FileUtils.rm_r tmpdir
  end

  def create_user(username, opts={})
    create_directory(directory, :owner => deployer, :group => deployer) do
      run "if ! id #{username} > /dev/null 2>&1; then #{sudo} useradd --no-create-home --home-dir #{opts[:homedir]} --shell #{opts[:shell]} #{username}; fi", :roles => "app"
    end
  end
  
  def create_directory(path, opts={})
    opts = { :owner => deployer, :group => deployer, :mode => "0755" }.merge(opts)
    run "#{sudo} mkdir -p #{path}", :roles => "app"
    yield if block_given?
    run "#{sudo} chmod #{opts[:mode]} #{path}"
    run "#{sudo} chown -R #{opts[:owner]}:#{opts[:group]} #{path}", :roles => "app"
  end
  
  def touch(path, opts={})
    opts = { :owner => deployer, :group => deployer, :mode => "0755" }.merge(opts)
    run "#{sudo} touch #{path}"
    run "#{sudo} chown #{opts[:owner]}:#{opts[:group]} #{path}", :roles => "app"
  end
  
  def render_template(path, opts={})
    opts = { :owner => deployer, :group => deployer, :mode => "0644" }.merge(opts)
    data = erb(File.read("templates/#{opts[:template]}"))
    filename = "/tmp/file-#{Time.now.to_i}"
    put data, filename
    run "#{sudo} mv #{filename} #{path}"
    run "#{sudo} chmod #{opts[:mode]} #{path}"
    run "#{sudo} chown -R #{opts[:owner]}:#{opts[:group]} #{path}", :roles => "app"
  end
  
  def upstart(path, opts={})
    render_template path, :template => opts[:template], :owner => "root", :group => "root"
  end
  
  def erb(text)
    ERB.new(text).result(binding)
  end

  def render_scripts
    template_names.each do |script_name|
      filename = tmpdir + "/scripts/" + script_name
      template = ERB.new(File.read(filename))
      rendered = template.result(binding)
      File.open(filename, "w") { |f| f.puts(rendered) }
    end
  end

  task :init do
    puts "Setting user and roles from config"
    if u = config_h[:user]
      puts "Setting user to #{u}"
      set :user, u
    end
    if roles = config_h[:roles]
      roles.each do |h,v|
        puts "Setting role #{h} => #{v}"
        role h, v
      end
    end
  end
  
  before :deploy, [:init]
  
  task :deploy do
    @deploy = build_deployment
    create_local_build
    download_artifact
    verify_plan
    make_release_directory
    transfer_build
    symlink
  end

end







