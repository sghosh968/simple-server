# frozen_string_literal: true

require "rails_helper"

RSpec.feature "Facility page functionality", type: :feature do
  let(:admin) { create(:admin, :power_user) }

  let!(:ihmi) { create(:organization, name: "IHMI") }
  let!(:another_organization) { create(:organization) }
  let!(:ihmi_group_bathinda) { create(:facility_group, organization: ihmi, name: "Bathinda") }
  let!(:unassociated_facility) { create(:facility, facility_group: nil, name: "testfacility") }
  let!(:unassociated_facility02) { create(:facility, facility_group: nil, name: "testfacility_02") }

  let!(:protocol_01) { create(:protocol, name: "testProtocol") }

  facility_page = AdminPage::Facilities::Show.new
  facility_group = AdminPage::FacilityGroups::New.new

  context "facility group listing" do
    context "admin has permission to manage facility groups" do
      before(:each) do
        visit root_path
        sign_in(admin.email_authentication)
        visit admin_facilities_path
      end

      it "Verify facility landing page" do
        facility_page.verify_facility_page_header
        expect(page).to have_content("IHMI")
        expect(page).to have_content("Bathinda")
      end

      context "when regions_prep is disabled" do
        it "create new facility group without assigning any facility" do
          facility_page.click_add_facility_group_button

          expect(page).to have_content("New facility group")
          facility_group.add_new_facility_group_without_assigning_facility(
            org_name: "IHMI",
            name: "testfacilitygroup",
            description: "testDescription",
            protocol_name: protocol_01.name
          )

          expect(page).to have_content("Bathinda")
          expect(page).to have_content("Testfacilitygroup")
        end

        it "create new facility group with facility" do
          facility_page.click_add_facility_group_button

          expect(page).to have_content("New facility group")
          facility_group.add_new_facility_group(
            org_name: "IHMI",
            name: "testfacilitygroup",
            description: "testDescription",
            protocol_name: protocol_01.name
          )

          expect(page).to have_content("Bathinda")
          expect(page).to have_content("Testfacilitygroup")
          facility_page.is_edit_button_present_for_facilitygroup("Testfacilitygroup")
        end
      end

      context "when regions_prep is enabled" do
        before do
          enable_flag(:regions_prep)
        end

        it "create new facility group without assigning any facility" do
          facility_page.click_add_facility_group_button

          expect(page).to have_content("New facility group")
          facility_group.add_new_facility_group_without_assigning_facility(
            org_name: "IHMI",
            name: "testfacilitygroup",
            description: "testDescription",
            protocol_name: protocol_01.name,
            state: "Punjab"
          )

          expect(page).to have_content("Bathinda")
          expect(page).to have_content("Testfacilitygroup")
        end

        it "create new facility group with facility" do
          facility_page.click_add_facility_group_button

          expect(page).to have_content("New facility group")
          facility_group.add_new_facility_group(
            org_name: "IHMI",
            name: "testfacilitygroup",
            description: "testDescription",
            protocol_name: protocol_01.name,
            state: "Punjab"
          )

          expect(page).to have_content("Bathinda")
          expect(page).to have_content("Testfacilitygroup")
          facility_page.is_edit_button_present_for_facilitygroup("Testfacilitygroup")
        end
      end

      it "admin should be able to delete facility group without facility " do
        facility_page.click_edit_button_present_for_facilitygroup(ihmi_group_bathinda.name)
        expect(page).to have_content("Edit facility group")
        facility_group.click_on_delete_facility_group_button
      end
    end
  end

  context "facility listing" do
    context "admin has permission to manage facilities for a facility group" do
      before(:each) do
        visit root_path
        sign_in(admin.email_authentication)
        visit admin_facilities_path
      end

      it "displays a new facility link" do
        expect(page).to have_link("Add a facility", href: new_admin_facility_group_facility_path(ihmi_group_bathinda))
      end
    end

    context "admin does not have permission to manage facilities at a facility group" do
      let(:admin) { create(:admin, :manager, accesses: [build(:access, resource: create(:facility_group))]) }

      before(:each) do
        visit root_path
        sign_in(admin.email_authentication)
        visit admin_facilities_path
      end

      it "does not display a new facility link" do
        expect(page).not_to have_link("Add a facility", href: new_admin_facility_group_facility_path(ihmi_group_bathinda))
      end
    end
  end
end
