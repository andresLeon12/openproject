#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
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
# See docs/COPYRIGHT.rdoc for more details.
#++

module API
  module V3
    module WorkPackages
      module EagerLoading
        class CustomField < Base
          def apply(work_package)
            work_package.custom_values.each do |cv|
              cv.custom_field = custom_field(cv.custom_field_id)
            end

            work_package.available_custom_fields = custom_fields_of(work_package)
          end

          def self.module
            CustomFieldAccessor
          end

          private

          def usages
            @usages ||= begin
              ActiveRecord::Base
                .connection
                .select_all(configured_fields_sql)
                .to_a
                .uniq
            end
          end

          def loaded_custom_fields
            @loaded_custom_fields ||= WorkPackageCustomField.where(id: usages.map { |u| u['custom_field_id'] }.uniq)
          end

          def custom_field(id)
            @loaded_custom_fields_by_id ||= begin
              loaded_custom_fields.map { |cf| [cf.id, cf] }.to_h
            end

            @loaded_custom_fields_by_id[id]
          end

          def usage_map
            @usage_map ||= begin
              usage_map = Hash.new do |by_project_hash, project_id|
                by_project_hash[project_id] = Hash.new do |by_type_hash, type_id|
                  by_type_hash[type_id] = []
                end
              end

              fields_by_id = loaded_custom_fields.to_a.map { |cf| [cf.id, cf] }.to_h

              usages.each do |usage_hash|
                usage_map[usage_hash['project_id']][usage_hash['type_id']] << fields_by_id[usage_hash['custom_field_id']]
              end

              usage_map
            end
          end

          def custom_fields_of(work_package)
            usage_map[work_package.project_id][work_package.type_id] +
              usage_map[nil][work_package.type_id]
          end

          def configured_fields_sql
            WorkPackageCustomField
              .left_joins(:projects, :types)
              .where(projects: { id: work_packages.map(&:project_id).uniq },
                     types: { id: work_packages.map(&:type_id).uniq })
              .or(WorkPackageCustomField
                    .left_joins(:projects, :types)
                    .references(:projects, :types)
                    .where(is_for_all: true))
              .select('projects.id project_id',
                      'types.id type_id',
                      'custom_fields.id custom_field_id')
              .to_sql
          end
        end

        module CustomFieldAccessor
          extend ActiveSupport::Concern

          # Because of the ruby method lookup,
          # wrapping the work_package here and define the
          # available_custom_fields methods on the wrapper does not suffice.
          # We thus extend each work package.
          included do
            def initialize(work_package)
              super
              work_package.extend(CustomFieldAccessorPatch)
            end
          end
        end

        module CustomFieldAccessorPatch
          def available_custom_fields
            @available_custom_fields
          end

          def available_custom_fields=(fields)
            @available_custom_fields = fields
          end
        end
      end
    end
  end
end
