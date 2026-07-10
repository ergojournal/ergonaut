class SentEmailsController < ApplicationController
  before_filter :assigned_area_editor_or_managing_editor
  before_filter :associated_email, only: [:show]
  before_filter :bread_crumbs
  
  def index
    @submission = Submission.find(params[:submission_id]) if params[:submission_id]
    @submission = Submission.find(params[:archive_id]) if params[:archive_id]    
    @referee_assignment = RefereeAssignment.find(params[:referee_assignment_id]) if params[:referee_assignment_id]
    
    if @referee_assignment
      @emails = SentEmail.where(submission_id: @submission.id, referee_assignment_id: @referee_assignment.id).order('created_at DESC')
    else
      @emails = SentEmail.where(submission_id: @submission.id).order('created_at DESC')
      # Area editors must not see emails sent or cc'd to the author: those reveal
      # the author's identity and break anonymity. Remove them entirely.
      @emails = hide_emails_to_author(@emails) unless current_user.managing_editor?
    end
  end

  def show
    @submission = Submission.find(params[:submission_id]) if params[:submission_id]
    @submission = Submission.find(params[:archive_id]) if params[:archive_id]
    @email = SentEmail.find(params[:id])
    # Block area editors from opening an author-addressed email, even by direct URL.
    redirect_to(security_breach_path) and return if !current_user.managing_editor? && involves_author?(@email)
  end

  private
  
    def assigned_area_editor_or_managing_editor
      unless managing_editor?
        if params[:submission_id] && current_user != Submission.find(params[:submission_id]).area_editor
          redirect_to security_breach_path
        end
      end
    end
    
    def associated_email
      if params[:submission_id]
        redirect_to security_breach_path unless SentEmail.find(params[:id]).submission == Submission.find(params[:submission_id])
      end
      if params[:referee_assignment_id]
        redirect_to security_breach_path unless SentEmail.find(params[:id]).referee_assignment == RefereeAssignment.find(params[:referee_assignment_id])
      end
    end

    # An email "involves the author" if it was addressed (To or Cc) to the
    # submitting author, or is one of the actions always sent to the author.
    def involves_author?(email)
      to_author?(email) || author_addressed?(email)
    end

    def to_author?(email)
      ['notify_au_decision_reached', 'confirm_au_submission_withdrawn'].include?(email.action)
    end

    def author_addressed?(email)
      return false unless @submission && @submission.author
      author_email = @submission.author.email.to_s.strip.downcase
      return false if author_email.empty?
      [email.to, email.cc].compact.any? { |field| field.to_s.downcase.include?(author_email) }
    end

    # Remove (not merely mask) every email to/cc the author so area editors
    # never see the author's identity in a submission's email log.
    def hide_emails_to_author(emails)
      emails.reject { |email| involves_author?(email) }
    end
end
