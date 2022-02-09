# frozen_string_literal: true

# name: discourse-reviewable-notification
# about: This plugin allows sending PMs for reviewables immediately after they get created
# version: 0.0.1
# authors: fzngagan
# url: https://github.com/paviliondev/discourse-reviewable-notification

enabled_site_setting :reviewable_notification_enabled

after_initialize do
  module ::ReviewablePostCreation
    def notify(count, user_ids)
      super
      return unless SiteSetting.reviewable_notification_enabled
      # if job is enqueued multiple times, we make sure that this code doesn't run more than once simultaneously
      DistributedMutex.synchronize("custom_send_reviewable_notification") do
        if SiteSetting.notify_about_flags_after > 0
          reviewable_ids = Reviewable
            .pending
            .default_visible
            .order('id DESC')
            .pluck(:id)

          if reviewable_ids.size > 0 && self.class.last_notified_id < reviewable_ids[0]
            usernames = active_moderator_usernames
            mentions = usernames.size > 0 ? "@#{usernames.join(', @')} " : ""

            @sent_reminder = PostCreator.create(
              Discourse.system_user,
              target_group_names: Group[:moderators].name,
              archetype: Archetype.private_message,
              subtype: TopicSubtype.system_message,
              title: I18n.t('system_messages.reviewables_reminder.subject_template'),
              raw: I18n.t('system_messages.reviewables_reminder.text_body_template', mentions: mentions, count: SiteSetting.notify_about_flags_after, base_url: Discourse.base_url)
            ).present?

            self.class.last_notified_id = reviewable_ids[0]
          end
        end
      end
    end
  end

  Jobs::NotifyReviewable.prepend ::ReviewablePostCreation

  add_class_method(Jobs::NotifyReviewable, :last_notified_id) do
    Discourse.redis.get(last_notified_key).to_i
  end

  add_class_method(Jobs::NotifyReviewable, :last_notified_id=) do |arg|
    Discourse.redis.set(last_notified_key, arg)
  end

  add_class_method(Jobs::NotifyReviewable, :last_notified_key) do
    "custom_last_notified_reviewable_id"
  end

  add_class_method(Jobs::NotifyReviewable, :clear_key) do
    Discourse.redis.del(last_notified_key)
  end

  add_to_class(Jobs::NotifyReviewable, :active_moderator_usernames) do
    User.where(moderator: true)
      .human_users
      .order('last_seen_at DESC')
      .limit(3)
      .pluck(:username)
  end

end
