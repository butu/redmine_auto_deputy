module RedmineAutoDeputy::IssueExtension
  extend ActiveSupport::Concern

  included do
    before_save :check_assigned_user_availability,  if: :recheck_availability_required?
  end

  private
  def check_assigned_user_availability
    return if self.assigned_to.nil? || !self.assigned_to.is_a?(User) || self.assigned_to == User.current

    check_date = [self.start_date, Time.now.to_date].compact.max

    original_assigned = self.assigned_to

    begin
      if self.assigned_to.available_at?(check_date)
        return true
      else # => need to assign someone else
        user_deputy = self.assigned_to.find_deputy(project_id: self.project.possible_project_id_for_deputies(original_assigned), date: check_date)
        if user_deputy
          self.assigned_to = user_deputy.deputy

          if self.current_journal.nil?
            self.init_journal(user_deputy.deputy)
          end

          if user_deputy.auto_watch_project_issues?
            self.add_watcher(original_assigned)
          end

          self.current_journal.notes = I18n.t('issue_assigned_to_changed', new_name: self.assigned_to.name, original_name: original_assigned.name)
          return true
        else
          self.errors.add(:assigned_to, I18n.t('activerecord.errors.issue.cant_be_assigned_due_to_unavailability',
            user_name: self.assigned_to.name, date: check_date.to_s, from: self.assigned_to.unavailable_from.to_s, to: self.assigned_to.unavailable_to.to_s))
          return false
        end
      end
    rescue Exception => e
      Rails.logger.error "Failed to check_assigned_user_availability for Issue ##{self.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      self.assigned_to = original_assigned
      return true
    end
  end

  private

  def recheck_availability_required?
    assigned_to_id_changed? || start_date_changed?
  end

end