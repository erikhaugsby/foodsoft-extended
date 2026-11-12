require_relative '../spec_helper'

feature 'editing and deleting messages', :js do
  include ActionText::SystemTestHelper

  let(:sender) { create(:user) }
  let(:recipient) { create(:user) }
  let!(:message) { create_message(sender: sender, recipient: recipient, subject: 'Pickup time', body: 'Pickup at five') }

  def create_message(sender:, recipient:, subject:, body:, reply_to: nil)
    message = Message.new(sender: sender, subject: subject, body: body, reply_to: reply_to)
    message.add_recipients([recipient.id])
    message.save!
    message
  end

  def edit_link
    "a[href='#{edit_message_path(message)}']"
  end

  def delete_link
    "a[data-method='delete'][href='#{message_path(message)}']"
  end

  it 'lets the sender change subject and text' do
    login sender
    visit message_path(message)
    find(edit_link).click
    fill_in 'message_subject', with: 'Pickup time changed'
    fill_in_rich_text_area with: 'Pickup at six'
    click_link_or_button I18n.t('messages.edit.submit')

    expect(page).to have_text I18n.t('messages.update.notice')
    expect(page).to have_text 'Pickup at six'
    expect(page).to have_text I18n.t('messages.show.edited_on')
    message.reload
    expect(message.subject).to eq 'Pickup time changed'
    expect(message).to be_edited
  end

  it 'lets the sender delete a message after confirming' do
    login sender
    visit message_path(message)
    accept_confirm { find(delete_link).click }

    expect(page).to have_text I18n.t('messages.destroy.notice')
    expect(message.reload).to be_deleted
    visit message_path(message)
    expect(page).to have_text I18n.t('messages.deleted')
    expect(page).to have_no_text 'Pickup at five'
  end

  it 'shows recipients neither edit nor delete' do
    login recipient
    visit message_path(message)
    expect(page).to have_text 'Pickup at five'
    expect(page).to have_no_css(edit_link)
    expect(page).to have_no_css(delete_link)
  end

  it 'lets an admin delete, but not edit, messages of others' do
    login create(:admin)
    visit message_path(message)
    expect(page).to have_no_css(edit_link)
    expect(page).to have_css(delete_link)
  end

  it 'keeps a placeholder in the thread, so replies still make sense' do
    create_message(sender: recipient, recipient: sender, subject: 'Re: Pickup time', body: 'Thanks!', reply_to: message.id)
    message.soft_delete!
    login sender
    visit thread_message_path(message)
    expect(page).to have_text I18n.t('messages.deleted')
    expect(page).to have_text 'Thanks!'
    expect(page).to have_no_text 'Pickup at five'
  end
end
