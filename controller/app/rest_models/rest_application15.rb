##
# @api REST
# Describes an Application
# @version 1.1
# @see RestApplication10
#
# Example:
#   ```
#   <application>
#     <embedded>
#     </embedded>
#     <framework>php-5.4</framework>
#     <name>testapp</name>
#     <creation-time>2013-02-20T08:29:49Z</creation-time>
#     <uuid>5124897d6892dfe819000005</uuid>
#     <aliases/>
#     <gear-count>1</gear-count>
#     <domain-id>localns</domain-id>
#     <gear-profile>small</gear-profile>
#     <scalable>false</scalable>
#     <git-url>ssh://5124897d6892dfe819000005@testapp-localns.example.com/~/git/testapp.git/</git-url>
#     <app-url>http://testapp-localns.example.com/</app-url>
#     <ssh-url>ssh://5124897d6892dfe819000005@testapp-localns.example.com</ssh-url>
#     <health-check-path>health_check.php</health-check-path>
#     <building-with nil="true"/>
#     <building-app nil="true"/>
#     <build-job-url nil="true"/>
#     <initial-git-url nil="true"/>
#     <links>
#       ...
#     </links>
#   </applications>
#   ```
#
# @!attribute [r] name
#   @return [String] Application name
# @!attribute [r] framework
#   @return [String] Web framework that runs on this application
# @!attribute [r] creation_time
#   @return [DateTime] Date and time the application was created
# @!attribute [r] uuid
#   @return [String] UUID for this application
# @!attribute [r] embedded
#   @return [Array<RestEmbeddedCartridge>] Array of support cartridges running in this application
# @!attribute [r] aliases
#   @return [Array<String>] Array of DNS aliases assocaited with this application
# @!attribute [r] gear_count
#   @return [Integer] Number of gears used by this application
# @!attribute [r] domain_id
#   @return [String] Namespace associated with this application
# @!attribute [r] git_url
#   @return [String] {http://git-scm.com/ Git} URL to access code for this application
# @!attribute [r] app_url
#   @return [String] The FQDN to access this application
# @!attribute [r] ssh_url
#   @return [String] username and FQDN that can be used to ssh into the primary application gear
# @!attribute [r] gear_profile
#   @return [String] The default gear profile that will be used to create gears for this application
# @!attribute [r] scalable
#   @return [Boolean] Indicates if the application is scalable (uses multiple gears) or not (all cartridges on the same gear)
# @!attribute [r] health_check_path
#   @return [String] HTTP URI which can be used to determine if the application is up and serving requests.
# @!attribute [r] building_with
#   @return [String] Name of cartridge used to initiate CI builds
# @!attribute [r] building_app
#   @return [String] Name of Application on which builds are run
# @!attribute [r] build_job_url
#   @return [String] URI on the CI server which represents the build job
# @!attribute [r] initial_git_url
#   @return [String] URI which was used to initialize the GIT repository for this application
# @!attribute [r] cartridges
#   @return [Array<RestCartridge>] List of cartridges in application. Used only when requesting application and included cartridges.
#   @see [ApplicationsController#index]
class RestApplication15 < OpenShift::Model
  attr_accessor :framework, :creation_time, :uuid, :embedded, :aliases, :name, :gear_count, :links, :domain_id, :git_url, :app_url, :ssh_url,
      :gear_profile, :scalable, :health_check_path, :building_with, :building_app, :build_job_url, :cartridges, :initial_git_url, :members

  def initialize(app, url, nolinks=false, applications=nil)
    self.embedded = {}
    app.requires(true).each do |feature|
      cart = CartridgeCache.find_cartridge(feature, app)

      # raise an exception in case the application cartridge is not found
      raise OpenShift::OOException.new("The application '#{app.name}' requires '#{feature}' but a matching cartridge could not be found") if cart.nil?

      if cart.categories.include? "web_framework"
        self.framework = cart.name
      else
        self.embedded[cart.name] = {info: ""}
      end
    end

    self.name = app.name
    self.creation_time = app.created_at
    self.uuid = app._id
    self.aliases = []
    app.aliases.each do |a|
      self.aliases << RestAlias.new(app, a, url, nolinks)
    end
    self.gear_count = app.num_gears
    self.domain_id = app.domain_namespace

    self.gear_profile = app.default_gear_size
    self.scalable = app.scalable

    self.git_url = "ssh://#{app.ssh_uri}/~/git/#{@name}.git/"
    self.app_url = "http://#{app.fqdn}/"
    self.ssh_url = "ssh://#{app.ssh_uri}"
    self.health_check_path = app.health_check_path

    self.building_with = nil
    self.building_app = nil
    self.build_job_url = nil
    self.initial_git_url = app.init_git_url

    self.members = app.members.map{ |m| RestMember.new(m, app.owner_id == m._id, url, nolinks) }

    app.component_instances.each do |component_instance|
      cart = CartridgeCache::find_cartridge(component_instance.cartridge_name, app)

      # add the builder properties if this is a builder component
      if cart.categories.include?("ci_builder")
        self.building_with = cart.name
        self.build_job_url = component_instance.component_properties["job_url"]

        # adding the job_url and "info" property for backward compatibility
        self.embedded[cart.name] = component_instance.component_properties
        self.embedded[cart.name]["info"] = "Job URL: #{component_instance.component_properties['job_url']}"
      else
        unless cart.categories.include? "web_framework"
          self.embedded[cart.name] = component_instance.component_properties

          # if the component has a connection_url property, add it as "info" for backward compatibility
          # make sure it is a hash, because copy-pasting the app document in mongo (using rockmongo UI) can convert hashes into arrays
          if component_instance.component_properties.is_a?(Hash) and component_instance.component_properties.has_key?("connection_url")
            self.embedded[cart.name]["info"] = "Connection URL: #{component_instance.component_properties['connection_url']}"
          end
        end
      end
    end

    #TODO this is way too inefficient.  Adding a bit of a hack to not have to call this all the time.
    app.domain.env_vars.each do |env_var|
      if env_var['key'] == 'JENKINS_URL'
        apps = applications || app.domain.applications
        apps.each do |domain_app|
          domain_app.component_instances.each do |component_instance|
            cart = CartridgeCache::find_cartridge(component_instance.cartridge_name, domain_app)
            if cart.categories.include?("ci")
              self.building_app = domain_app.name
              break
            end
          end
        end
        break
      end
    end

    unless nolinks
      carts = CartridgeCache.find_cartridge_by_category("embedded", app).map{ |c| c.name }

      self.links = {
        "GET" => Link.new("Get application", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}")),
        "GET_DESCRIPTOR" => Link.new("Get application descriptor", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/descriptor")),
        #"GET_GEARS" => Link.new("Get application gears", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/gears")),
        "GET_GEAR_GROUPS" => Link.new("Get application gear groups", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/gear_groups")),
        "START" => Link.new("Start application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "start")
        ]),
        "STOP" => Link.new("Stop application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "stop")
        ]),
        "RESTART" => Link.new("Restart application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "restart")
        ]),
        "FORCE_STOP" => Link.new("Force stop application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "force-stop")
        ]),
        "SCALE_UP" => Link.new("Scale up application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "scale-up")
        ]),
        "SCALE_DOWN" => Link.new("Scale down application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "scale-down")
        ]),
        "TIDY" => Link.new("Tidy the application framework", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "tidy")
        ]),
        "RELOAD" => Link.new("Reload the application", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "reload")
        ]),
        "THREAD_DUMP" => Link.new("Trigger thread dump", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/events"), [
          Param.new("event", "string", "event", "thread-dump")
        ]),
        "DELETE" => Link.new("Delete application", "DELETE", URI::join(url, "domains/#{@domain_id}/applications/#{@name}")),
        "ADD_CARTRIDGE" => Link.new("Add embedded cartridge", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/cartridges"),[
            Param.new("name", "string", "framework-type, e.g.: mongodb-2.2", carts)
          ],[
            OptionalParam.new("colocate_with", "string", "The component to colocate with", app.component_instances.map{|c| c.cartridge_name}),
            OptionalParam.new("scales_from", "integer", "Minimum number of gears to run the component on."),
            OptionalParam.new("scales_to", "integer", "Maximum number of gears to run the component on."),
            OptionalParam.new("additional_storage", "integer", "Additional GB of space to request on all gears running this component."),
            (OptionalParam.new("url", "string", "A URL to a downloadable cartridge.") if Rails.application.config.openshift[:download_cartridges_enabled]),
            OptionalParam.new("environment_variables", "array", "Add or Update application environment variables, e.g.:[{'name':'FOO', 'value':'123'}, {'name':'BAR', 'value':'abc'}]")
          ].compact
        ),
        "LIST_CARTRIDGES" => Link.new("List embedded cartridges", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/cartridges")),
        "DNS_RESOLVABLE" => Link.new("Resolve DNS", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/dns_resolvable")),
        "ADD_ALIAS" => Link.new("Create new alias", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/aliases"),
          [Param.new("id", "string", "Alias for application")],
          [OptionalParam.new("ssl_certificate", "string", "Content of SSL Certificate"),
            OptionalParam.new("private_key", "string", "Private key for the certificate.  Required if adding a certificate"),
            OptionalParam.new("pass_phrase", "string", "Optional passphrase for the private key")]),
        "LIST_ALIASES" => Link.new("List application aliases", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/aliases")),
        "LIST_MEMBERS" => Link.new("List members of this application", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/members")),
        "SET_UNSET_ENVIRONMENT_VARIABLES" => Link.new("Add/Update/Delete one or more environment variables", "POST", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/environment-variables"), nil, [
          OptionalParam.new("name", "string", "Name of the environment variable to add/update"),
          OptionalParam.new("value", "string", "Value of the environment variable"),
          OptionalParam.new("environment_variables", "array", "Add/Update/Delete application environment variables, e.g. Add/Update: [{'name':'FOO', 'value':'123'}, {'name':'BAR', 'value':'abc'}], Delete: [{'name':'FOO'}, {'name':'BAR'}]")
        ]),
        "LIST_ENVIRONMENT_VARIABLES" => Link.new("List all environment variables", "GET", URI::join(url, "domains/#{@domain_id}/applications/#{@name}/environment-variables"))
      }
    end
  end

  def to_xml(options={})
    options[:tag_name] = "application"
    super(options)
  end
end
