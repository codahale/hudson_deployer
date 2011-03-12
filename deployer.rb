require 'capistrano'
require 'rest_client'
require 'json'

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
    [:application, :version, :user, :build_num, :artifact_url].each do |f|
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
  _cset(:version) { abort ":version must be set (e.g. 2.0.0)" }
  _cset(:user) { abort ":user must be set" }
  _cset(:directory) { "/opt/#{application}" }
  _cset(:current_release) { "#{directory}/#{Time.now.to_i}" }

  def hud_api(url)
    JSON.parse(RestClient.get(url + "/api/json"))
  end

  def job
    @job ||= begin
      record = hud_api(hudson)["jobs"].find { |j| j["name"] == application }
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

  def ensure_directory
    run "#{sudo} mkdir -p #{directory}", :roles => "app"
    run "#{sudo} chown -R #{user} #{directory}", :roles => "app"
  end
  
  def make_release_directory
    run "#{sudo} mkdir -p #{current_release}", :roles => "app"
    run "#{sudo} chown -R #{user} #{current_release}", :roles => "app"
  end

  task :deploy do
    @deploy = build_deployment
    @deploy.debug
    ensure_directory
    create_local_build
    make_release_directory
    transfer_build
    bounce_server
  end

end







