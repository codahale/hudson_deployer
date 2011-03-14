require 'capistrano'
require 'rest_client'
require 'json'
require 'erb'

class Deploy
  attr_accessor :application, 
                :version, 
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
    [:application, :version, :user, :build_num].each do |f|
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

  _cset(:hudson) { abort ":hudson must be set (e.g. build.yammer.com)" }
  _cset(:application) { abort ":application must be set" }
  _cset(:build) { abort ":build must be set (e.g. app-release)" }
  _cset(:version) { abort ":version must be set (e.g. 2.0.0)" }
  _cset(:user) { abort ":user must be set" }
  _cset(:directory) { "/opt/#{application}" }
  _cset(:current_release) { "#{directory}/releases/#{Time.now.to_i}" }

  def hud_api(url)
    JSON.parse(RestClient.get(url + "/api/json"))
  end

  def job
    @job ||= begin
      record = hud_api(hudson)["jobs"].find { |j| j["name"] == build }
      raise "No such hudson build could be found" if !record
      hud_api(record["url"])
    end
  end
  
  def latest_build
    @latest_build ||= begin
      builds = job["builds"]
      raise "There are no existing builds for this project" if builds.empty?
      url = builds.first["url"]
      hud_api(url)
    end
  end
  
  def check_latest_build
    if latest_build["result"] != "SUCCESS"
      raise "The last build was not successful: #{build["result"]}"
    end
    if latest_build["building"] == true
      raise "Project is currently building. You must wait until it finishes."
    end
  end
  
  def resolve_artifact_url
    @artifact_url = begin
      artifacts = latest_build["artifacts"]
      raise "No artifacts exist for this project!" if artifacts.empty?
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
      latest_build["url"] + "artifact/" + artifact["relativePath"]
    end
  end
  
  def artifact_filename
    @artifact_url.split("/").last
  end
  
  def build_deployment
    check_latest_build
    Deploy.new do |d|
      d.application = application
      d.version = version
      d.user = user
      d.build_num = latest_build["number"]
      d.artifact_url = resolve_artifact_url
    end
  end

  def ensure_remote_directory
    run "#{sudo} mkdir -p #{directory}", :roles => "app"
    run "#{sudo} chown -R #{user} #{directory}", :roles => "app"
  end
  
  def make_release_directory
    run "#{sudo} mkdir -p #{current_release}", :roles => "app"
    run "#{sudo} chown -R #{user} #{current_release}", :roles => "app"
  end
  
  def create_local_tmp_directory
    @tmpdir = "/tmp/deployer-#{Time.now.to_i}"
    FileUtils.mkdir_p(@tmpdir)
  end
  
  def local_entries
    Dir.entries(File.expand_path(File.dirname(__FILE__) + "/" + application))
  end
  
  def local_actions
    local_entries.select { |f| f =~ /\.erb$/ }
  end
  
  def create_local_build
    from = File.expand_path(File.dirname(__FILE__) + "/" + application)
    local_entries.reject { |f| f =~ /^\./ || f == "Capfile" || f =~ /\.erb$/ }.
      each { |f| FileUtils.cp_r f, @tmpdir, :verbose => true }
  end
  
  def verify_plan
    puts "*" * 80
    puts "Deployment plan:"
    @deploy.debug
    puts "Copying assets:"
    puts `find #{@tmpdir}`
    puts "The following actions will be rendered and executed on the remote host:"
    local_actions.each { |a| puts ">> #{a} "}
    puts "*" * 80
    unless Capistrano::CLI.ui.ask("Is this what you want?") =~ /^y.*/i
      exit
    end
  end

  def download_artifact
    puts "Downloading artifact..."
    `wget #{@deploy.artifact_url} -O #{@tmpdir}/#{artifact_filename}`
  end

  def render_actions
    local_actions.each do |file|
      puts "Rendering action: " + file
      template = ERB.new(File.read(file))
      rendered = template.result(binding)
      new_filename = file.split(".").reverse.drop(1).reverse.join(".")
      File.open("#{@tmpdir}/#{new_filename}", "w") { |f| f.puts(rendered) }
    end
  end

  def transfer_build
    puts "Transferring build..."
    Dir.entries(@tmpdir).each do |e|
      unless e =~ /^\./
        upload e, "#{current_release}/#{e}", :roles => "app"
      end
    end
  end
  
  def cleanup
    FileUtils.rm_r @tmpdir
  end
  
  def rollback
  end
  
  task :deploy do
    @deploy = build_deployment
    ensure_remote_directory
    create_local_tmp_directory
    create_local_build
    download_artifact
    render_actions
    verify_plan
    
    make_release_directory
    begin
      transfer_build
      # bounce_server
    rescue StandardError => ex
      rollback
    end
    
    cleanup
  end

end







