require 'spec_helper'

describe "Author Center" do
  
  let(:user) { create(:user) }
  let(:area_editor) { create(:area_editor) }
  let!(:managing_editor) { create(:managing_editor) }
  
  let!(:desk_rejected_submission) { create(:desk_rejected_submission) }
  let!(:accepted_submission) { create(:accepted_submission) }
  
  subject { page }

  context "when logged in as author/referee" do
    before { valid_sign_in(user) }
    
    # new
    describe "new submission page" do
      before { visit new_author_center_path }
      
      it "offers a form for submitting a paper" do
        expect(page).to have_content('Submit a paper')
        expect(page).to have_field('Title')
        expect(page).to have_field('Area')
        expect(page).to have_field('File')
        expect(page).to have_button('Submit')
      end
    end
    
    # create
    describe "creating a submission" do
      before { visit new_author_center_path }
      
      context "with valid inputs" do
        before do
          fill_in 'Title', with: 'Valid Test Submission'
          attach_file('File', File.join(Rails.root, 'spec', 'support', 'Sample Submission.pdf'))
          click_button 'Submit'
        end
        
        it { should have_success_message('received') }
        
        it "lists the user's submissions" do
          for sub in user.submissions do
            expect(page).to have_content(sub.title)
          end
        end
        
        it "has a working link to the manuscript" do
          page.all(:link, 'Download').last.click
          expect(page.response_headers['Content-Type']).to eq 'application/pdf'
        end
        
        it "emails the managing editors" do
          expect(deliveries).to include_email(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Valid Test Submission')
          expect(SentEmail.all).to include_record(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Valid Test Submission')
        end
      end
      
      context "with a missing title" do
        before do
          reset_email
          attach_file('File', File.join(Rails.root, 'spec', 'support', 'Sample Submission.pdf'))
          click_button 'Submit'
        end
        
        it "doesn't create a new submission" do
          expect(user.reload.submissions).to be_empty
        end
        
        it "displays alert and describes error" do
          expect(page).to have_error_message('error')
          expect(page).to have_content 'can\'t be blank'
        end
        
        it "re-renders the page for a new submission" do
          expect(page).to have_field 'Title'
        end
        
        it "doesn't email the managing editors" do
          expect(deliveries).not_to include_email(subject_begins: 'New Submission', to: managing_editor.email)
        end
      end
      
      context "with no file attached" do
        before do
          fill_in 'Title', with: 'Some Clever Title'
          click_button 'Submit'
        end
        
        it "doesn't create a new submission" do
          expect(user.reload.submissions).to be_empty
        end
        
        it "displays alert and describes error" do
          expect(page).to have_error_message('error')
          expect(page).to have_content 'can\'t be blank'
        end
        
        it "re-renders the page for a new submission" do
          expect(page).to have_field 'Title'
        end
        
        it "doesn't email the managing editors" do
          expect(deliveries).not_to include_email(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
          expect(SentEmail.all).not_to include_record(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
        end
      end
      
      context "with a large file (>5MB) attached" do
        before do
          fill_in 'Title', with: 'Oversize Submission'
          attach_file('File', File.join(Rails.root, 'spec', 'support', 'Oversize Submission.pdf'))
          click_button 'Submit'
        end
        
        it "doesn't create a new submission" do
          expect(user.reload.submissions).to be_empty
        end
        
        it "displays alert and describes error" do
          expect(page).to have_error_message('error')
          expect(page).to have_content 'can\'t be larger than'
        end
        
        it "re-renders the page for a new submission" do
          expect(page).to have_field 'Title'
        end
        
        it "doesn't email the managing editors" do
          expect(deliveries).not_to include_email(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
          expect(SentEmail.all).not_to include_record(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
        end
      end
      
      context "with a forbidden file extension" do
        before do
          fill_in 'Title', with: 'Some Clever Title'
          attach_file('File', File.join(Rails.root, 'spec', 'support', 'Bad Sample Submission.sql'))
          click_button 'Submit'
        end
        
        it "doesn't create a new submission" do
          expect(user.reload.submissions).to be_empty
        end
        
        it "displays alert and describes error" do
          expect(page).to have_error_message('error')
          expect(page).to have_content 'not allowed'
        end
        
        it "re-renders the page for a new submission" do
          expect(page).to have_field 'Title'
        end
        
        it "doesn't email the managing editors" do
          expect(deliveries).not_to include_email(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
          expect(SentEmail.all).not_to include_record(subject_begins: 'New Submission', to: managing_editor.email, body_includes: 'Some Clever Title')
        end
      end
    end
    
    # index # TODO: add tests of table-row coloring functionality
    describe "listing submissions" do
      context "with one fresh submission" do
        before do
          @fresh_submission = create(:submission, author: user)
          visit author_center_index_path
        end
        
        it "displays only the fresh submission" do
          expect(page).to have_content(@fresh_submission.title)
          expect(page).not_to have_content(desk_rejected_submission.title)
          expect(page).not_to have_content(accepted_submission.title)
        end
      end
      
      context "with one fresh submission and one desk rejected submission" do
        before do
          @fresh_submission = create(:submission, author: user)
          @desk_rejected_submission = create(:desk_rejected_submission, author: user)
          visit author_center_index_path
        end
        
        it "displays only the fresh submission" do
          expect(page).to have_content(@fresh_submission.title)
          expect(page).not_to have_content(@desk_rejected_submission.title)
        end
      end
      
      context "with one fresh submission, one under review, and one accepted" do
        before do
          @fresh_submission = create(:submission, author: user)
          @under_review_submission = create(:submission_sent_out_for_review, author: user)
          @accepted_submission = create(:desk_rejected_submission, author: user)
          visit author_center_index_path
        end
        
        it "displays only the fresh and under review submissions" do
          expect(page).to have_content(@fresh_submission.title)
          expect(page).to have_content(@under_review_submission.title)
          expect(page).not_to have_content(@accepted_submission.title)
        end
      end
    end
    
    # archives
    describe "listing archived submissions" do
      context "with one fresh submission" do
        before do
          @fresh_submission = create(:submission, author: user)
          visit archives_author_center_index_path
        end
        
        it "says there are no archived submissions" do
          expect(page).to have_content('No archived submissions')
        end
      end
      
      context "with one fresh submission and one desk rejected submission" do
        before do
          @fresh_submission = create(:submission, author: user)
          @desk_rejected_submission = create(:desk_rejected_submission, author: user)
          visit archives_author_center_index_path
        end
        
        it "displays only the desk rejected submission" do
          expect(page).to have_content(@desk_rejected_submission.title)
          expect(page).not_to have_content(@fresh_submission.title)
        end
        
        it "has a working download link to the desk rejected manuscript file" do
          click_link 'Download'
          expect(page.response_headers['Content-Type']).to eq 'application/pdf'
        end
      end
      
      context "with one fresh submission, one accepted, and one desk rejected" do
        before do
          @fresh_submission = create(:submission, author: user)
          @accepted_submission = create(:accepted_submission, author: user)
          @desk_rejected_submission = create(:desk_rejected_submission, author: user)
          visit archives_author_center_index_path
        end
        
        it "displays only the accepted and desk rejected submissions" do
          expect(page).not_to have_content(@fresh_submission.title)          
          expect(page).to have_content(@accepted_submission.title)
          expect(page).to have_content(@desk_rejected_submission.title)
        end
        
        it "has working download links to the accepted and rejected manuscript files" do
          first_link = page.all(:link, 'Download').first
          second_link = page.all(:link, 'Download').last
          first_link.click
          expect(page.response_headers['Content-Type']).to eq 'application/pdf'
          second_link.click
          expect(page.response_headers['Content-Type']).to eq 'application/pdf'
        end
    
      end
    end
    
    # withdraw
    describe "withdrawing a submission" do
      context "when the submission is fresh" do
        before do
          @fresh_submission = create(:submission, author: user)
          visit author_center_index_path
          find_withdraw_link(@fresh_submission).click         
        end
        
        it "withdraws and archives the submission" do
          @fresh_submission.reload
          expect(@fresh_submission).to be_withdrawn
          expect(@fresh_submission).to be_archived
        end
        
        it "emails the editors and authors but no referees" do
          expect(deliveries).to include_email(subject_begins: 'Submission Withdrawn', to: managing_editor.email)
          expect(SentEmail.all).to include_record(subject_begins: 'Submission Withdrawn', to: managing_editor.email)
          
          expect(deliveries).to include_email(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: managing_editor.email)
          expect(SentEmail.all).to include_record(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: managing_editor.email)
                                                    
          expect(deliveries).not_to include_email(subject_begins: 'Withdrawn Submission')
          expect(SentEmail.all).not_to include_record(subject_begins: 'Withdrawn Submission')
        end
        
        it "flashes success and takes the user back to their list of submissions" do
          expect(page.current_path).to eq(author_center_index_path)
          expect(page).to have_success_message('withdrawn')
        end
        
        it "no longer lists the submission" do
          within('table') do
            expect(page).not_to have_content(@fresh_submission.title)
          end
        end
      end
      
      context "when the submission has been sent out for review" do
        before do
          @submission_under_review = create(:submission_sent_out_for_review, author: user)
          visit author_center_index_path
          find_withdraw_link(@submission_under_review).click
        end
        
        it "withdraws and archives the submission" do
          @submission_under_review.reload
          expect(@submission_under_review).to be_withdrawn
          expect(@submission_under_review).to be_archived
        end
        
        it "emails the editors, authors, and referees" do
          area_editor = @submission_under_review.area_editor
          
          expect(deliveries).to include_email(subject_begins: 'Submission Withdrawn', to: area_editor.email, cc: managing_editor.email)
          expect(SentEmail.all).to include_record(subject_begins: 'Submission Withdrawn', to: area_editor.email, cc: managing_editor.email)
          
          expect(deliveries).to include_email(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: area_editor.email)
          expect(SentEmail.all).to include_record(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: area_editor.email)
          expect(deliveries).to include_email(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: managing_editor.email)
          expect(SentEmail.all).to include_record(subject_begins: 'Confirmation: Submission Withdrawn', to: user.email, cc: managing_editor.email)

          @submission_under_review.pending_referee_assignments.each do |assignment|
            expect(deliveries).to include_email(subject_begins: 'Withdrawn Submission', to: assignment.referee.email, cc: area_editor.email)
            expect(SentEmail.all).to include_record(subject_begins: 'Withdrawn Submission', to: assignment.referee.email, cc: area_editor.email)
          end
        end
        
        it "flashes success and takes the user back to their list of submissions" do
          expect(page.current_path).to eq(author_center_index_path)
          expect(page).to have_success_message('withdrawn')
        end
        
        it "no longer lists the submission" do
          within('table') do
            expect(page).not_to have_content(@submission_under_review.title)
          end
        end
      end
    end
  end
  
  shared_examples_for "no actions are accessible" do |redirect_path|
    # new
    describe "new submission page" do
      before { visit new_author_center_path }
      
      it "redirects to #{redirect_path}" do
        expect(current_path).to eq(send(redirect_path))
      end
    end
    
    # create
    describe "create submission" do
      before do
        @params = { title: 'Some Clever Title', area_id: '1' }        
      end
      
      it "doesn't create a new submission" do
        expect { 
          post author_center_index_path, submission: @params 
        }.not_to change { Submission.count }
      end
      
      it "redirects to #{redirect_path}" do
        post author_center_index_path, submission: @params
        expect(response).to redirect_to(send(redirect_path))
      end
      
    end
    
    # index
    describe "index submissions" do
      before { visit author_center_index_path }
      
      it "redirects to #{redirect_path}" do
        expect(current_path).to eq(send(redirect_path))
      end
    end
    
    # archives
    describe "archive submissions" do
      before { visit archives_author_center_index_path }
      
      it "redirects to #{redirect_path}" do
        expect(current_path).to eq(send(redirect_path))
      end
    end
    
    # withdraw
    describe "withdraw submission" do
      before do
        @submission = create(:submission)
        visit withdraw_author_center_path(@submission)
      end
      
      it "doesn't withdraw the submission" do
        expect(@submission.withdrawn?).to eq(false)
      end
      
      it "redirects to #{redirect_path}" do
        expect(current_path).to eq(send(redirect_path))
      end
    end
  end
  
  context "when logged in as an editor" do
    before { valid_sign_in(managing_editor) }
    
    it_behaves_like "no actions are accessible", :security_breach_path
  end
  
  context "when not logged in" do
    it_behaves_like "no actions are accessible", :signin_path
  end
  
end
