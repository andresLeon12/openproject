#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++require 'rspec'

require 'spec_helper'
require_relative './eager_loading_mock_wrapper'

describe ::API::V3::WorkPackages::EagerLoading::CustomField do
  let!(:work_package) { FactoryGirl.create(:work_package) }
  let!(:type) { work_package.type }
  let!(:other_type) { FactoryGirl.create(:type) }
  let!(:project) { work_package.project }
  let!(:other_project) { FactoryGirl.create(:project) }
  let!(:type_project_cf) do
    FactoryGirl.create(:list_wp_custom_field).tap do |cf|
      type.custom_fields << cf
      project.work_package_custom_fields << cf
    end
  end
  let!(:for_all_type_cf) do
    FactoryGirl.create(:list_wp_custom_field, is_for_all: true).tap do |cf|
      type.custom_fields << cf
    end
  end
  let!(:for_all_other_type_cf) do
    FactoryGirl.create(:list_wp_custom_field, is_for_all: true).tap do |cf|
      other_type.custom_fields << cf
    end
  end
  let!(:type_other_project_cf) do
    FactoryGirl.create(:list_wp_custom_field).tap do |cf|
      type.custom_fields << cf
      other_project.work_package_custom_fields << cf
    end
  end
  let!(:other_type_project_cf) do
    FactoryGirl.create(:list_wp_custom_field).tap do |cf|
      other_type.custom_fields << cf
      project.work_package_custom_fields << cf
    end
  end

  describe '.apply' do
    it 'preloads the available_custom_fields' do
      wrapped = EagerLoadingMockWrapper.wrap_all(described_class, [work_package])

      expect(work_package)
        .not_to receive(:available_custom_fields)

      wrapped.each do |w|
        expect(w.available_custom_fields)
          .to match_array [type_project_cf, for_all_type_cf]
      end
    end
  end
end
