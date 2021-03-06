class Admin::FacilityGroupsController < AdminController
  before_action :set_facility_group, only: [:show, :edit, :update, :destroy]
  before_action :set_organizations, only: [:new, :edit, :update, :create]
  before_action :set_protocols, only: [:new, :edit, :update, :create]
  before_action :set_available_states, only: [:new, :create, :edit, :update], if: -> { Flipper.enabled?(:regions_prep) }
  before_action :set_blocks, only: [:edit, :update], if: -> { Flipper.enabled?(:regions_prep) }
  around_action :wrap_in_transaction, only: [:edit, :update], if: -> { Flipper.enabled?(:regions_prep) }

  def show
    @facilities = @facility_group.facilities.order(:name)
    @users = @facility_group.users.order(:full_name)
  end

  def new
    @facility_group = FacilityGroup.new

    authorize { current_admin.accessible_organizations(:manage).any? }
  end

  def edit
  end

  def create
    @facility_group = FacilityGroup.new(facility_group_params)

    authorize { current_admin.accessible_organizations(:manage).find(@facility_group.organization.id) }

    if @facility_group.save && @facility_group.toggle_diabetes_management
      update_block_regions if Flipper.enabled?(:regions_prep)
      redirect_to admin_facilities_url, notice: "FacilityGroup was successfully created."
    else
      render :new
    end
  end

  def update
    if @facility_group.update(facility_group_params) && @facility_group.toggle_diabetes_management
      update_block_regions if Flipper.enabled?(:regions_prep)
      redirect_to admin_facilities_url, notice: "FacilityGroup was successfully updated."
    else
      render :edit
    end
  end

  def destroy
    if @facility_group.discardable?
      @facility_group.discard
      redirect_to admin_facilities_url, notice: "FacilityGroup was successfully deleted."
    else
      redirect_to admin_facilities_url, alert: "FacilityGroup cannot be deleted, please move patient data and try again."
    end
  end

  private

  def set_organizations
    # include the facility group's organization along with the ones you can access
    @organizations = current_admin.accessible_organizations(:manage).presence || [@facility_group.organization]
  end

  def set_protocols
    @protocols = Protocol.all
  end

  def set_facility_group
    @facility_group = authorize { current_admin.accessible_facility_groups(:manage).friendly.find(params[:id]) }
  end

  def set_available_states
    @available_states = CountryConfig.current[:states]
  end

  def set_blocks
    district_region = Region.find_by(source: @facility_group)
    @blocks = district_region&.block_regions&.order(:name) || []
  end

  def wrap_in_transaction
    ActiveRecord::Base.transaction do
      yield
    end
  end

  def facility_group_params
    params.require(:facility_group).permit(
      :organization_id,
      :name,
      :state,
      :description,
      :protocol_id,
      :enable_diabetes_management
    )
  end

  def blocks_params
    params.require(:facility_group).permit(
      new_blocks: [],
      remove_blocks: []
    )
  end

  def update_block_regions
    ManageDistrictRegionService.update_blocks(district_region: @facility_group.region,
                                              new_blocks: blocks_params[:new_blocks],
                                              remove_blocks: blocks_params[:remove_blocks])
  end
end
