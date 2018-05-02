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
#++

module API
  module Caching
    class CacheChecksumWrapper < SimpleDelegator
      attr_accessor :work_package,
                    :cache_checksum

      def initialize(work_package, checksum)
        super(work_package)
        self.work_package = work_package
        self.cache_checksum = checksum
      end
      private_class_method :new

      def self.wrap(work_packages)
        eager_load_custom_fields(work_packages)

        concat = <<-SQL
          MD5(CONCAT(statuses.id,
                     statuses.updated_at,
                     users.id,
                     users.updated_on,
                     responsibles_work_packages.id,
                     responsibles_work_packages.updated_on,
                     assigned_tos_work_packages.id,
                     assigned_tos_work_packages.updated_on,
                     versions.id,
                     versions.updated_on,
                     types.id,
                     types.updated_at,
                     enumerations.id,
                     enumerations.updated_at,
                     categories.id,
                     categories.updated_at))
        SQL

        checksums = WorkPackage
                    .where(id: work_packages.map(&:id).uniq)
                    .left_joins(:status, :author, :responsible, :assigned_to, :fixed_version, :priority, :category, :type)
                    .pluck('work_packages.id', concat)
                    .group_by(&:first)

        project_ids = work_packages.map do |work_package|
          [work_package.project_id, work_package.parent && work_package.parent.project_id] +
            work_package.children.map(&:project_id)
        end

        projects = Project
                   .includes(:enabled_modules)
                   .where(id: project_ids.flatten.uniq.compact)
                   .to_a

        projects_by_id = projects.map { |p| [p.id, p] }.to_h

        work_packages.map do |work_package|
          # assign projects to work_package, children and parent

          work_package.project = projects_by_id[work_package.project_id]
          work_package.parent.project = projects_by_id[work_package.parent.project_id] if work_package.parent

          work_package.children.each do |child|
            child.project = projects_by_id[child.project_id]
          end

          work_package.custom_values.each do |cv|
            cv.custom_field = @loaded_custom_fields_by_id[cv.custom_field_id]
          end

          work_package.available_custom_fields = custom_fields_of(work_package)

          new(work_package, checksums[work_package.id].last.last)
        end
      end

      def self.eager_load_custom_fields(work_packages)
        configured_fields = WorkPackageCustomField
                            .left_joins(:projects, :types)
                            .where(projects: { id: work_packages.map(&:project_id).uniq },
                                   types: { id: work_packages.map(&:type_id).uniq })
                            .or(WorkPackageCustomField
                                .left_joins(:projects, :types)
                                .references(:projects, :types)
                                .where(is_for_all: true))

        usages = ActiveRecord::Base
                 .connection
                 .select_all(configured_fields
                               .select('projects.id project_id',
                                       'types.id type_id',
                                       'custom_fields.id custom_field_id')
                               .to_sql)
                 .to_a
                 .uniq

        usage_map = Hash.new do |by_project_hash, project_id|
          by_project_hash[project_id] = Hash.new do |by_type_hash, type_id|
            by_type_hash = []
          end
        end

        @loaded_custom_fields = WorkPackageCustomField.where(id: usages.map { |u| u['custom_field_id'] })
        @loaded_custom_fields_by_id = @loaded_custom_fields.map { |cf| [cf.id, cf] }.to_h

        @loaded_custom_field_map = begin
          fields_by_id = @loaded_custom_fields.to_a.group_by(&:id)

          usages.each do |usage_hash|
            usage_map[usage_hash['project_id']][usage_hash['type_id']] << fields_by_id[usage_hash['custom_field_id']]
          end

          usage_map
        end
      end

      def self.custom_fields_of(work_package)
        @loaded_custom_field_map[work_package.project_id][work_package.type_id] +
          @loaded_custom_field_map[nil][work_package.type_id]
      end
    end
  end
end
