## Overview

This gem was written to help simplify Java deployments using fat-jar hudson builds.

## Example Capfile

	require 'hudson_deployer'

	set  :hudson, "build.company.com"
	set  :application, "project"
	set  :build, "project-release"
	set  :version, "2.0.0"
	set  :deployer, "deploy"

	config[:default] = { 
	  :jdbc_url => "jdbc:mysql://localhost:3306/project" 
	}

	config[:staging] = {
	  :user => "cvandyck",
	  :roles => {
	    :app => "192.168.185.132"
	  }
	}

	config[:production] = {
	  :user => "admin",
	  :roles => {
	    :app => "production-001"
	  }
	}

	before :deploy do
	  if @env == :production
	    run "#{sudo} apt-get install sun-java6-jdk dbus hal -y"
	  else
	    run "#{sudo} apt-get install openjdk-6-jdk dbus hal -y"
	  end
	  create_user deployer, :homedir => "/opt/project", :shell => "/bin/sh"
	  create_directory "/var/log/project"
	  touch "/var/log/project/sysout.log"
	end

	after :deploy do
	  render_template "/etc/project.conf", :template => "project.conf.erb", :mode => "0600"
	  render_template "/etc/project.jvm.conf", :template => "#{@env}/project.jvm.conf.erb", :mode => "0644"
	  upstart "/etc/init/project.conf", :template => "upstart.conf.erb"
	  run "#{sudo} stop project || true"
	  sleep 5
	  run "#{sudo} start project"
	end

## Templates

Templates are kept in a folder called "templates".  They can be named anything, but to make your life easier suffix them with .erb.  Render templates with 

	render_template("/etc/broccoli", :template => "broccoli.erb")

Note that the :template parameter assumes a path relative to the templates folder.

Templates are rendered using the same scope binding as the gem itself. They therefore can access configuration (described below).

## Upstart

Servers are bounced using upstart. In the above example, we use upstart to render an upstart configuration file for our project.  Actual upstart commands are done using the Capistrano run command

## Staging vs Production

It is assumed that unless otherwise specified, it will be run in staging mode. To use production,

	cap production deploy

## Configuration

Configuration can be set on a per-environment basis or for all environments. Set configuration variables using the config hash:

	config[:default] = { 
	  :jdbc_url => "jdbc:mysql://localhost:3306/project" 
	}
	
Set per-environment configuration:

	config[:production] = {
	  :user => "admin",
	  :roles => {
	    :app => "production-001"
	  }
	}

The :user and :roles keys are special and change the way that Capistrano works, as expected.  You may also set any other key/value pair you wish. The combined configuration is available through the config_h parameter:

	"database": {
	    "jdbc_url": "<%= config_h[:jdbc_url] %>",
	    "driver_class": "com.vertica.Driver"
	}

## Other Stuff

&copy; Collin VanDyck 2011. Distributed under the MIT license.

