class RevisionsController < ApplicationController
  
  before_filter :author_of_submission

  def new
    @submission = Submission.find(params[:author_center_id])
    @revised_submission = Submission.new
    @revised_submission.title = @submission.title
  end

  def create
    @current_user = current_user
    @original_submission = Submission.find(params[:author_center_id])

    if @original_submission.submit_revision(params[:submission])
      redirect_to author_center_index_path
    else
      render :new
    end   
  end
  
  private 
  
    def author_of_submission
      redirect_to security_breach_path unless Submission.find(params[:author_center_id]).author == current_user
    end

end
