require 'fileutils'
class Courseware::Repository

  def initialize(config)
    @config = config

    if system('git status >/dev/null 2>&1')
      @valid_repo = true
      configure_courseware
    else
      @valid_repo = false
      $logger.debug "Not in a courseware repository"
    end
  end


  def toplevel
    message = 'This task should be run from the repository root'
    raise message unless Dir.pwd == `git rev-parse --show-toplevel`.chomp
  end

  def courselevel
    message = 'This task must be run from within a course directory'
    raise message unless File.expand_path("#{Dir.pwd}/..") == `git rev-parse --show-toplevel`.chomp
  end

  def tag(tag, message=nil)
    if tag
      system("git tag -a #{tag} -m '#{message}'")
    else
      system("git tag #{tag}")
    end

    system("git push upstream master")
    system("git push upstream #{tag}")
    system("git push courseware master")
    system("git push courseware #{tag}")
  end

  def update
    system('git fetch upstream')
    system('git fetch upstream --tags')
  end

  def create(branch)
    system("git checkout -b #{branch}")
    system("git push upstream #{branch}")
  end

  def checkout(branch, pull=false)
    system("git checkout #{branch}")
    system("git pull upstream #{branch}") if pull
  end

  def merge(branch)
    system('git checkout master')
    system("git merge #{branch}")
    system('git push upstream master')
  end

  def delete(branch)
    system("git branch -d #{branch}")
    system("git push upstream --delete #{branch}")
  end

  def on_branch?(branch='master')
    raise "You do not appear to be on the #{branch} branch" unless `git symbolic-ref -q --short HEAD`.chomp == branch
  end

  def clean?
    raise "Your working directory has local modifications." unless system('git diff-index --quiet HEAD')
  end

  def branch_exists?(branch)
    `git branch --list #{branch}` == branch
  end

  def releasenotes(last, version)
    str = "### #{version}\n"

    `git log --pretty="format:%h]X[%aN]X[%aE]X[%cd]X[%s" #{last}..HEAD`.split("\n").each do |line|
      commit, author, email, date, title = line.split(']X[')

      # Bail on merge commits, we want to credit the original author
      next if title =~ /^Merge pull request #/

      # Bail if the commit didn't change this course
      next unless `git diff --name-only #{commit}^..#{commit} 2>/dev/null` =~ /^#{File.basename(Dir.pwd)}/

      str << "* #{title}\n"
      str << "    * _[#{author}](#{email}): #{date}_\n"
      str << "    * _#{commit}_\n"
    end
    str
  end

private

  def configure_courseware
    courseware = "#{@config[:github][:public]}/#{@config[:github][:repository]}"
    upstream   = "#{@config[:github][:development]}/#{@config[:github][:repository]}"

    # Check the origin to see which scheme we should use
    origin = `git config --get remote.origin.url`.chomp
    if origin =~ /^(git@|https:\/\/)github.com[:\/].*\/#{@config[:github][:repository]}(?:-.*)?(?:.git)?$/
      case $1
      when 'git@'
        ensure_remote('courseware', "git@github.com:#{courseware}.git")
        ensure_remote('upstream',   "git@github.com:#{upstream}.git")
      when 'https://'
        ensure_remote('courseware', "https://github.com/#{courseware}.git")
        ensure_remote('upstream',   "https://github.com/#{upstream}.git")
      end
    else
      raise "Your origin (#{origin}) does not appear to be configured correctly."
    end
  end

  def ensure_remote(remote, url)
  # If we *have* the remote, but it's not correct, then  let's repair it.
    if `git config --get remote.#{remote}.url`.chomp != url and $?.success?
      if Courseware.confirm("Your '#{remote}' remote should be #{url}. May I correct this?")
        raise "Error correcting remote." unless system("git remote remove #{remote}")
      else
        raise "Please configure your '#{remote}' remote before proceeding."
      end
    end

    unless system("git config --get remote.#{remote}.url > /dev/null")
      # Add the remote if it doesn't already exist
      unless system("git remote add #{remote} #{url}")
        raise "Could not add the '#{remote}' remote."
      end
    end
  end

end
