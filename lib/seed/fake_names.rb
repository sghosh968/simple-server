module Seed
  class FakeNames
    include Singleton
    def initialize
      @csv = CSV.read(Rails.root.join("db/fake_names.csv").to_s, headers: true).by_col!
      @organization_names = @csv["Organizations"].compact
      @villages = @csv["Villages/Cities"].compact
      @male_first_names = @csv["Male First Names"].compact
      @female_first_names = @csv["Female First Names"].compact
    end

    def _csv
      @csv
    end

    def org_name
      @organization_names.sample
    end

    def seed_org_name
      @organization_names.first
    end

    def village
      @villages.sample
    end
  end
end