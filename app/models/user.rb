class User < ApplicationRecord
  include PgSearch::Model

  AUTHENTICATION_TYPES = {
    email_authentication: "EmailAuthentication",
    phone_number_authentication: "PhoneNumberAuthentication"
  }
  ACCESS_LEVELS = {
    viewer: {
      name: "viewer",
      grant_access: [],
      description: "Can view stuff"
    },

    manager: {
      name: "manager",
      grant_access: [:viewer, :manager],
      description: "Can manage stuff"
    },

    power_user: {
      name: "power_user",
      grant_access: [:viewer, :manager, :power_user],
      description: "Can manage everything"
    }
  }

  enum sync_approval_status: {
    requested: "requested",
    allowed: "allowed",
    denied: "denied"
  }, _prefix: true
  enum access_level: ACCESS_LEVELS.map { |level, metadata| [level, metadata[:name]] }.to_h, _suffix: :access

  belongs_to :organization, optional: true
  has_many :user_authentications
  has_many :blood_pressures
  has_many :patients, -> { distinct }, through: :blood_pressures
  has_many :registered_patients,
    inverse_of: :registration_user,
    class_name: "Patient",
    foreign_key: :registration_user_id
  has_many :phone_number_authentications,
    through: :user_authentications,
    source: :authenticatable,
    source_type: "PhoneNumberAuthentication"
  has_many :email_authentications,
    through: :user_authentications,
    source: :authenticatable,
    source_type: "EmailAuthentication"
  has_many :appointments
  has_many :medical_histories
  has_many :prescription_drugs
  has_many :user_permissions, foreign_key: :user_id, dependent: :delete_all
  has_many :accesses, dependent: :destroy
  has_many :deleted_patients,
    inverse_of: :deleted_by_user,
    class_name: "Patient",
    foreign_key: :deleted_by_user_id

  pg_search_scope :search_by_name, against: [:full_name], using: {tsearch: {prefix: true, any_word: true}}
  scope :search_by_email,
    ->(term) { joins(:email_authentications).merge(EmailAuthentication.search_by_email(term)) }
  scope :search_by_phone,
    ->(term) { joins(:phone_number_authentications).merge(PhoneNumberAuthentication.search_by_phone(term)) }
  scope :search_by_name_or_email, ->(term) { search_by_name(term).union(search_by_email(term)) }
  scope :search_by_name_or_phone, ->(term) { search_by_name(term).union(search_by_phone(term)) }

  validates :full_name, presence: true
  validates :role, presence: true, if: -> { email_authentication.present? }
  # validates :access_level, presence: true, if: -> { email_authentication.present? }
  validates :device_created_at, presence: true
  validates :device_updated_at, presence: true

  delegate :registration_facility,
    :access_token,
    :logged_in_at,
    :has_never_logged_in?,
    :mark_as_logged_in,
    :phone_number,
    :otp,
    :otp_valid?,
    :facility_group,
    :password_digest, to: :phone_number_authentication, allow_nil: true
  delegate :email,
    :password,
    :authenticatable_salt,
    :invited_to_sign_up?, to: :email_authentication, allow_nil: true

  after_destroy :destroy_email_authentications

  def phone_number_authentication
    phone_number_authentications.first
  end

  def email_authentication
    email_authentications.first
  end

  def registration_facility_id
    registration_facility.id
  end

  alias facility registration_facility

  def authorized_facility?(facility_id)
    registration_facility && registration_facility.facility_group.facilities.where(id: facility_id).present?
  end

  def access_token_valid?
    sync_approval_status_allowed?
  end

  def self.build_with_phone_number_authentication(params)
    phone_number_authentication = PhoneNumberAuthentication.new(
      phone_number: params[:phone_number],
      password_digest: params[:password_digest],
      registration_facility_id: params[:registration_facility_id]
    )
    phone_number_authentication.set_otp
    phone_number_authentication.set_access_token

    user = new(
      id: params[:id],
      full_name: params[:full_name],
      organization_id: params[:organization_id],
      device_created_at: params[:device_created_at],
      device_updated_at: params[:device_updated_at]
    )
    user.sync_approval_requested(I18n.t("registration"))

    user.phone_number_authentications = [phone_number_authentication]
    user
  end

  def update_with_phone_number_authentication(params)
    user_params = params.slice(:full_name, :sync_approval_status, :sync_approval_status_reason)
    phone_number_authentication_params = params.slice(
      :phone_number,
      :password,
      :password_digest,
      :registration_facility_id
    )

    transaction do
      update!(user_params) && phone_number_authentication.update!(phone_number_authentication_params)
    end
  end

  def sync_approval_denied(reason = "")
    self.sync_approval_status = :denied
    self.sync_approval_status_reason = reason
  end

  def sync_approval_allowed(reason = "")
    self.sync_approval_status = :allowed
    self.sync_approval_status_reason = reason
  end

  def sync_approval_requested(reason)
    self.sync_approval_status = :requested
    self.sync_approval_status_reason = reason
  end

  def authorized?(permission_slug, resource: nil)
    user_permissions.find_by(permission_slug: permission_slug, resource: resource).present?
  end

  def has_permission?(permission_slug)
    user_permissions.where(permission_slug: permission_slug).present?
  end

  def reset_phone_number_authentication_password!(password_digest)
    transaction do
      authentication = phone_number_authentication
      authentication.password_digest = password_digest
      authentication.set_access_token
      sync_approval_requested(I18n.t("reset_password"))
      authentication.save!
      save!
    end
  end

  def self.requested_sync_approval
    where(sync_approval_status: :requested)
  end

  def has_role?(*roles)
    roles.map(&:to_sym).include?(role.to_sym)
  end

  def resources
    user_permissions.map(&:resource)
  end

  # #########################
  # User Access (permissions)
  #
  def accessible_organizations(action)
    return Organization.all if power_user?
    accesses.organizations(action)
  end

  def accessible_facility_groups(action)
    return FacilityGroup.all if power_user?
    accesses.facility_groups(action)
  end

  def accessible_facilities(action)
    return Facility.all if power_user?
    accesses.facilities(action)
  end

  def can?(action, model, record = nil)
    return true if power_user?
    accesses.can?(action, model, record)
  end

  def access_tree(action)
    facilities = accessible_facilities(action).includes(facility_group: :organization)

    facility_tree =
      facilities
        .map { |facility| [facility, {can_access: true}] }
        .to_h

    facility_group_tree =
      facilities
        .map(&:facility_group)
        .map { |fg|
          display_facilities = facility_tree.select { |facility, _| facility.facility_group == fg }

          [fg,
            {
              can_access: can?(action, :facility_group, fg),
              facilities: display_facilities,
              total_facilities: fg.facilities.size
            }
          ]
        }
        .to_h

    organization_tree =
      facilities
        .map(&:facility_group)
        .map(&:organization)
        .map { |org|
          display_facility_groups = facility_group_tree.select { |facility_group, _| facility_group.organization == org }

          [org,
            {
              can_access: can?(action, :organization, org),
              facility_groups: display_facility_groups,
              total_facility_groups: org.facility_groups.size
            }
          ]
        }
        .to_h

    {organizations: organization_tree}
  end

  def grantable_access_levels
    ACCESS_LEVELS[access_level.to_sym][:grant_access]
  end

  def grant_access(user, selected_facility_ids)
    raise unless grantable_access_levels.include?(user.access_level)

    selected_facilities = Facility.where(id: selected_facility_ids)
    resources = []

    selected_facilities.group_by(&:organization).each do |org, selected_facilities_in_org|
      if can?(:manage, :organization, org) && org.facilities == selected_facilities_in_org
        resources << {resource: org}
        selected_facilities -= selected_facilities_in_org
      end
    end

    selected_facilities.group_by(&:facility_group).each do |fg, selected_facilities_in_fg|
      if can?(:manage, :facility_group, fg) && fg.facilities == selected_facilities_in_fg
        resources << {resource: fg}
        selected_facilities -= selected_facilities_in_fg
      end
    end

    selected_facilities.each do |f|
      resources << {resource: f} if can?(:manage, :facility, f)
    end

    resources = resources.flatten

    raise if resources.empty?
    user.accesses.create!(resources)
  end

  #
  # #########################

  def destroy_email_authentications
    destroyable_email_auths = email_authentications.load

    user_authentications.each(&:destroy)
    destroyable_email_auths.each(&:destroy)

    true
  end

  def flipper_id
    "User;#{id}"
  end

  def power_user?
    power_user_access? && email_authentication.present?
  end
end
