class Comment

  def before_create
    self.target ||= project

    case target
    when Task then set_status_and_assigned
    when Project then create_a_parent_conversation
    end
  end

  def after_create
    return unless target
    target.reload
    
    @activity = project && project.log_activity(self, 'create')

    target.after_comment(self)      if target.respond_to?(:after_comment)
    target.add_watchers(@mentioned) if target.respond_to?(:add_watchers)
    target.add_watchers(self.user)  if target.respond_to?(:add_watchers)
    target.notify_new_comment(self) if target.respond_to?(:notify_new_comment)
  end
  
  def after_destroy
    Activity.destroy_all :target_type => self.class.to_s, :target_id => self.id
  end
  
  protected

    def set_status_and_assigned
      self.previous_status      = target.previous_status
      self.assigned             = target.assigned
      self.previous_assigned_id = target.previous_assigned_id
      if status == Task::STATUSES[:open] && !assigned
        self.assigned = Person.find(:first, :conditions => { :user_id => user.id, :project_id => project.id })
      elsif status != Task::STATUSES[:open]
        self.assigned = nil
      end
    end

    def create_a_parent_conversation
      # We create an empty conversation, skipping validations, to attach the comment to it
      conversation = project.new_conversation(user, :simple => true)
      conversation.save(false)
      self.target = conversation
    end

end