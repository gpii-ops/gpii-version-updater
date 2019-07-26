#!/usr/bin/env ruby


require "docker-api"
require "yaml"

class SyncImages

  CONFIG_FILE = "../gpii-infra/shared/versions.yml"
  CREDS_FILE = "./creds.json"
  DESIRED_COMPONENTS = ["dataloader", "flowmanager", "preferences", "productiontests"]
  DESIRED_COMPONENTS_ALL_TOKEN = "ALL"
  DESIRED_COMPONENTS_DEFAULT_TOKEN = "DEFAULT"
  PUSH_TO_GCR = false
  REGISTRY_URL = "gcr.io/gpii-common-prd"

  def self.load_config(config_file)
    return YAML.load(File.read(config_file))
  end

  def self.login()
    puts "Logging in with credentials from #{SyncImages::CREDS_FILE}..."
    creds = File.read(SyncImages::CREDS_FILE)
    Docker.authenticate!(
      "username" => "_json_key",
      "password" => creds,
      "serveraddress" => "https://gcr.io",
    )
  end

  def self.process_config(config, desired_components, push_to_gcr, registry_url)
    if desired_components == SyncImages::DESIRED_COMPONENTS_ALL_TOKEN
      components = config.keys.sort.each
    elsif desired_components == SyncImages::DESIRED_COMPONENTS_DEFAULT_TOKEN
      components = SyncImages::DESIRED_COMPONENTS
    else
      components = desired_components.split("|")
    end

    components.each do |component|
      begin
        repository = config[component]["upstream"]["repository"]
        tag = config[component]["upstream"]["tag"]
      rescue
        puts "Could not find desired component #{component} (or its 'repository' or 'tag' attributes)! Skipping!"
        next
      end
      (new_repository, sha, tag) = self.process_image(component, repository, tag, registry_url, push_to_gcr)
      config[component]["generated"] = {
        "repository" => new_repository,
        "sha" => sha,
        "tag" => tag,
      }
    end
    return config
  end

  def self.process_image(component, repository, tag, registry_url, push_to_gcr)
    puts "Processing image for #{component}..."
    image = self.pull_image(repository, tag)
    if push_to_gcr
      new_repository = self.retag_image(image, registry_url, repository, tag)
      self.push_image(image, new_repository, tag)
      # Re-pull image so that we (consistently) get the SHA based on the pushed image.
      image = self.pull_image(new_repository, tag)
      sha = self.get_sha_from_image(image, new_repository)
    else
      new_repository = repository
      sha = self.get_sha_from_image(image, new_repository)
    end
    puts "Done with #{component}."
    puts

    return [new_repository, sha, tag]
  end

  def self.pull_image(repository, tag)
    puts "Pulling #{repository}..."
    image = Docker::Image.create({"fromImage" => repository, "tag" => tag}, creds: {})
    return image
  end

  def self.get_sha_from_image(image, new_repository)
    sha = nil

    # First, try to find an image matching our re-tagged repository.
    image.info["RepoDigests"].each do |digest|
      if digest.start_with?(new_repository)
        sha = digest.split('@')[1]
        break
      end
    end

    # If that doesn't work (sometimes Docker doesn't have a RepoDigest for the
    # re-tagged image), try to return the first RepoDigest.
    unless sha
      begin
        image_with_sha = image.info["RepoDigests"][0]
        sha = image_with_sha.split('@')[1]
      rescue
        raise ArgumentError, "Could not find sha! image.info was #{image.info}"
      end
    end

    puts "Got image with sha #{sha}..."
    return sha
  end

  def self.retag_image(image, registry_url, repository, tag)
    # Many applications (Docker Hub, GKE Binary Authorization
    # admission_whitelist_patterns) do not support slashes after the "username"
    # component (e.g. host.name/username/image).
    new_repository = "#{registry_url}/#{repository.gsub("/", "__")}"
    puts "Retagging #{repository} as #{new_repository}..."
    image.tag("repo" => new_repository, "tag" => tag)
    return new_repository
  end

  def self.push_image(image, new_repository, tag)
    puts "Pushing #{new_repository}..."
    # Docker.push collects output from the API call via 'response_block()', a
    # kind of callback function. Docker.push ignores errors and discards
    # output, though the output is available to a block passed to Docker.push.
    # Hence, we use a block to look for errors and explode if we find one.
    repo_tag = "#{new_repository}:#{tag}"
    image.push(nil, repo_tag: repo_tag) do |output_line|
      puts "...output from push: #{output_line}"
      if output_line.include? '"error":'
        raise ArgumentError, "Found error message in output (see above)!"
      end
    end
  end

  def self.write_new_config(config_file, config)
    header = """# versions.yml
#
# This file is managed by https://github.com/gpii-ops/gpii-version-updater.
#
# See the README for details on how to modify which images are used or to add
# components.
"""
    File.open(config_file, "w") do |f|
      f.write(header)
      f.write(YAML.dump(config))
    end
  end

end


def main(config_file, desired_components, push_to_gcr, registry_url)
  if config_file.nil? or config_file.empty?
    config_file = SyncImages::CONFIG_FILE
  end
  if desired_components.nil? or desired_components.empty?
    desired_components = SyncImages::DESIRED_COMPONENTS_DEFAULT_TOKEN
  end
  if push_to_gcr.nil? or push_to_gcr.empty?
    push_to_gcr = SyncImages::PUSH_TO_GCR
  end
  # Due to how we pass arguments through rake, 'false' ends up as a string.
  # Correct it into a boolean.
  push_to_gcr = false if push_to_gcr == "false"
  if registry_url.nil? or registry_url.empty?
    registry_url = SyncImages::REGISTRY_URL
  end

  config = SyncImages.load_config(config_file)
  SyncImages.login() if push_to_gcr
  SyncImages.process_config(config, desired_components, push_to_gcr, registry_url)
  SyncImages.write_new_config(config_file, config)
end


# vim: et ts=2 sw=2:
