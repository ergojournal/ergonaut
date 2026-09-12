module SentEmailsHelper
  def linkify_email_list(list)
    return "" if list.blank?
    addresses = list.split(', ')
    addresses.map! { |a| mail_to(a) }
    addresses.join(', ').html_safe
  end
end
