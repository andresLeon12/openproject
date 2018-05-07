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
      class WorkPackageEagerLoadingWrapper < SimpleDelegator
        private_class_method :new

        class << self
          def wrap_all(ids_in_order, current_user)
            work_packages = add_eager_loading(WorkPackage.where(id: ids_in_order), current_user).to_a

            eager_load_ancestry(work_packages, ids_in_order, current_user)

            work_packages = wrap_and_apply(work_packages, eager_loader_classes_all)

            eager_load_user_custom_values(work_packages)
            eager_load_version_custom_values(work_packages)
            eager_load_list_custom_values(work_packages)

            work_packages.sort_by { |wp| ids_in_order.index(wp.id) }
          end

          def wrap(work_package)
            containers = eager_loader_classes_one
                           .map { |klass| klass.new([work_package]) }

            work_package.extend(::API::V3::WorkPackages::EagerLoading::CacheChecksumAccessorPatch)

            containers.each do |container|
              container.apply(work_package)
            end

            work_package
          end

          private

          def wrap_and_apply(work_packages, container_classes)
            containers = container_classes
                         .map { |klass| klass.new(work_packages) }

            work_packages = work_packages.map do |work_package|
              new(work_package)
            end

            containers.each do |container|
              work_packages.each do |work_package|
                container.apply(work_package)
              end
            end

            work_packages
          end

          def eager_loader_classes_one
            [
              ::API::V3::WorkPackages::EagerLoading::Checksum
            ]
          end

          def eager_loader_classes_all
            [
              ::API::V3::WorkPackages::EagerLoading::Hierarchy,
              ::API::V3::WorkPackages::EagerLoading::Project,
              ::API::V3::WorkPackages::EagerLoading::Checksum,
              ::API::V3::WorkPackages::EagerLoading::CustomValue,
              ::API::V3::WorkPackages::EagerLoading::CustomField,
              ::API::V3::WorkPackages::EagerLoading::CustomAction
            ]
          end

          def add_eager_loading(scope, current_user)
            scope
              .includes(WorkPackageRepresenter.to_eager_load)
              .include_spent_hours(current_user)
              .select('work_packages.*')
              .distinct
          end

          def eager_load_ancestry(work_packages, ids_in_order, current_user)
            grouped = WorkPackage.aggregate_ancestors(ids_in_order, current_user)

            work_packages.each do |wp|
              wp.work_package_ancestors = grouped[wp.id] || []
            end
          end

          def eager_load_user_custom_values(work_packages)
            eager_load_custom_values work_packages, 'user', User.includes(:preference)
          end

          def eager_load_version_custom_values(work_packages)
            eager_load_custom_values work_packages, 'version', Version
          end

          def eager_load_list_custom_values(work_packages)
            eager_load_custom_values work_packages, 'list', CustomOption
          end

          def eager_load_custom_values(work_packages, field_format, scope)
            cvs = custom_values_of(work_packages, field_format)

            ids_of_values = cvs.map(&:value).select { |v| v =~ /\A\d+\z/ }

            return if ids_of_values.empty?

            values_by_id = scope.where(id: ids_of_values).group_by(&:id)

            cvs.each do |cv|
              next unless values_by_id[cv.value.to_i]
              cv.value = values_by_id[cv.value.to_i].first
            end
          end

          def custom_values_of(work_packages, field_format)
            cvs = []

            work_packages.each do |wp|
              wp.custom_values.each do |cv|
                cvs << cv if cv.custom_field && cv.custom_field.field_format == field_format && cv.value.present?
              end
            end

            cvs
          end
        end

        eager_loader_classes_all.each do |klass|
          include(klass.module)
        end
      end
    end
  end
end
