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

      #def define_all_custom_field_accessors
      #  binding.pry
      #  available_custom_fields.each do |custom_field|
      #    add_custom_field_accessors custom_field
      #  end
      #end

      def self.wrap(work_packages)
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

        all_fields = WorkPackageCustomField
                     .includes(:custom_options)
                     .left_joins(:projects, :types)
                     .where(projects: { id: work_packages.map(&:project_id).uniq },
                            types: { id: work_packages.map(&:type_id).uniq })
                     .or(WorkPackageCustomField
                           .includes(:custom_options)
                           .left_joins(:projects, :types)
                           .references(:projects, :types)
                           .where(is_for_all: true))

        usages = ActiveRecord::Base
                 .connection
                 .select_all(all_fields
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

        fields_by_id = all_fields.to_a.group_by(&:id)

        usages.each do |usage_hash|
          usage_map[usage_hash['project_id']][usage_hash['type_id']] << fields_by_id[usage_hash['custom_field_id']]
        end

        work_packages.map do |work_package|
          type_key = work_package.type_id

          fields = usage_map[work_package.project_id][work_package.type_id] +
                   usage_map[nil][work_package.type_id]

          work_package.available_custom_fields = fields

          new(work_package, checksums[work_package.id].last.last)
        end
      end
    end
  end
end
