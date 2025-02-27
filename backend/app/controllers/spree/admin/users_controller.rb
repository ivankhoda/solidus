# frozen_string_literal: true

module Spree
  module Admin
    class UsersController < ResourceController
      rescue_from ActiveRecord::DeleteRestrictionError, with: :user_destroy_with_orders_error

      after_action :sign_in_if_change_own_password, only: :update

      before_action :load_roles, only: [:index, :edit, :new]
      before_action :load_stock_locations, only: [:edit, :new]

      def index
        respond_with(@collection) do |format|
          format.html
        end
      end

      def show
        redirect_to edit_admin_user_path(@user)
      end

      def create
        @user = Spree.user_class.new(user_params)
        if @user.save
          set_roles
          set_stock_locations

          flash[:success] = t('spree.created_successfully')
          redirect_to edit_admin_user_url(@user)
        else
          load_roles
          load_stock_locations

          flash.now[:error] = @user.errors.full_messages.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      def update
        if @user.update(user_params)
          set_roles
          set_stock_locations

          flash[:success] = t('spree.account_updated')
          redirect_to edit_admin_user_url(@user)
        else
          load_roles
          load_stock_locations

          flash.now[:error] = @user.errors.full_messages.join(", ")
          render :edit, status: :unprocessable_entity
        end
      end

      def addresses
        if request.put?
          if @user.update(user_params)
            flash.now[:success] = t('spree.account_updated')
          end

          render :addresses
        end
      end

      def orders
        params[:q] ||= {}
        @search = Spree::Order.reverse_chronological.ransack(params[:q].merge(user_id_eq: @user.id))
        @orders = @search.result.page(params[:page]).per(Spree::Config[:admin_products_per_page])
      end

      def items
        params[:q] ||= {}

        @search = Spree::Order.includes(
          line_items: {
            variant: [:product, { option_values: :option_type }]
          }
).ransack(params[:q].merge(user_id_eq: @user.id))

        @orders = @search.result.page(params[:page]).per(Spree::Config[:admin_products_per_page])
      end

      def model_class
        Spree.user_class
      end

      private

      def collection
        return @collection if @collection

        @search = super.ransack(params[:q])
        @collection = @search.result.includes(:spree_roles)
        @collection = @collection.includes(:orders)
        @collection = @collection.page(params[:page]).per(Spree::Config[:admin_products_per_page])
      end

      def user_params
        attributes = permitted_user_attributes

        if action_name == "create" || can?(:update_email, @user)
          attributes |= [:email]
        end

        if can? :manage, Spree::Role
          attributes += [{ spree_role_ids: [] }]
        end

        if can? :manage, Spree::StockLocation
          attributes += [{ stock_location_ids: [] }]
        end

        unless can? :update_password, @user
          attributes -= [:password, :password_confirmation]
        end

        params.require(:user).permit(attributes)
      end

      # handling raise from Spree::Admin::ResourceController#destroy
      def user_destroy_with_orders_error
        invoke_callbacks(:destroy, :fails)
        render status: :forbidden, plain: t("spree.error_user_destroy_with_orders")
      end

      def sign_in_if_change_own_password
        if try_spree_current_user == @user && @user.password.present?
          sign_in(@user, event: :authentication, bypass: true)
        end
      end

      def load_roles
        @roles = Spree::Role.accessible_by(current_ability)
        if @user
          @user_roles = @user.spree_roles
        end
      end

      def load_stock_locations
        @stock_locations = Spree::StockLocation.accessible_by(current_ability)
      end

      def set_roles
        if user_params[:spree_role_ids]
          @user.spree_roles = Spree::Role.accessible_by(current_ability).where(id: user_params[:spree_role_ids])
        end
      end

      def set_stock_locations
        if user_params[:stock_location_ids]
          @user.stock_locations =
            Spree::StockLocation.accessible_by(current_ability).where(id: user_params[:stock_location_ids])
        end
      end
    end
  end
end
