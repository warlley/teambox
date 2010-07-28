# TODO: Make it run on Heroku
class OpenidController < ApplicationController
  skip_before_filter :login_required

  # Starts the redirect authorization for OpenID
  def start
    @provider = params[:provider]

    config = APP_CONFIG['openid_providers'][@provider]
    raise "Provider #{@provider} is missing. Please add the key and secret to the configuration file." unless config

    authenticate_with_open_id(
      config['endpoint'], 
      :return_to => openid_callback_url, 
      :required => [
        'http://axschema.org/namePerson/first', 
        'http://axschema.org/namePerson/last', 
        'http://axschema.org/contact/email'])
  end

  def callback
    @provider = params[:provider]
    begin
      @config = APP_CONFIG['openid_providers'][@provider]
      raise "Provider #{@provider} is missing. Please add the key and secret to the configuration file." unless @config

      response = request.env[Rack::OpenID::RESPONSE]
      if response.status != :success
        flash[:notice] = t(:'openid.provider_error', :provider => @provider) 
        return redirect_to login_path
      end

      load_profile(response)
      
      # Cleanup if there's an app link not assigned to a user yet
      AppLink.find_by_provider_and_app_user_id_and_user_id(@provider, @profile[:id],nil).try(:destroy)

      if logged_in?
        if current_user.app_links.find_by_provider(@provider)
          flash[:notice] = t(:'oauth.already_linked_to_your_account')
        elsif AppLink.find_by_provider_and_app_user_id(@provider, @profile[:id])
          flash[:error] = t(:'oauth.already_taken_by_other_account')
        else
          current_user.link_to_app(@provider, @profile)
          flash[:success] = t(:'oauth.account_linked')
        end
        return redirect_to(account_linked_accounts_path)
      else
        if openid_login
          flash[:success] = t(:'oauth.logged_in')
          return redirect_to projects_path
        elsif User.find_by_email(@profile[:email])
          # TODO: locate existing user by email and ask to log in to link him
          flash[:notice] = t(:'oauth.user_already_exists_by_email', :email => @profile[:email])
          return redirect_to login_path
        elsif User.find_by_login(@profile[:login])
          flash[:notice] = t(:'oauth.user_already_exists_by_login', :login => @profile[:login])
          return redirect_to login_path
        else
          unless @invitation || signups_enabled?
            flash[:error] = t(:'users.new.no_public_signup')
            return redirect_to login_path
          end

          logout_keeping_session!
          @user = User.new(@profile)
          @user.confirmed_user = true
          @user.password = User.generate_password
          @user.password_confirmation = @user.password
          app_link = AppLink.create!(:provider => @provider, 
                                     :app_user_id => @profile[:id], 
                                     :custom_attributes => @profile[:original])
                                     
          if @user && @user.save && @user.errors.empty?
            self.current_user = @user
            if app_link
              app_link.user = @user
              app_link.save!
            end
      
            if @invitation
              if @invitation.project
                redirect_to(project_path(@invitation.project))
              else
                redirect_to(group_path(@invitation.group))
              end
            else
              redirect_back_or_default root_path
            end
            flash[:success] = t(:'users.create.thanks')
          else
            profile_for_session = @profile
            profile_for_session.delete(:original)
            session[:profile] = profile_for_session
            session[:app_link] = app_link.id
            
            flash[:notice] = 'Errores: ' + @user.errors.inspect
            
            return redirect_to signup_path
          end
       end
      end
    rescue Exception => e
      render :text => %(<p>OpenID Error #{e.message}</p><p>#{$!}</p><p><a href="/openid/#{@provider}">Retry</a></p>)
    end
  end

  private
    # Logs in with the chosen provider, if the AppLink exists
    def openid_login
      user = AppLink.find_by_provider_and_app_user_id(@provider, @profile[:id]).try(:user)
      !!self.current_user = user
    end
  
    # Loads user's openid profile in @profile
    def load_profile(response)
      @profile = {}
      ax = OpenID::AX::FetchResponse.from_success_response(response)
      @profile[:id]      = ax ? ax["http://axschema.org/contact/email"].first : sreg['email']
      @profile[:email]      = ax ? ax["http://axschema.org/contact/email"].first : sreg['email']
      @profile[:login]      = @profile[:email].split(/@/).flatten.first
      @profile[:first_name] = ax ? ax["http://axschema.org/namePerson/first"].first : sreg['first']
      @profile[:last_name]  = ax ? ax["http://axschema.org/namePerson/last"].first : sreg['last']
      @profile[:login]      = User.find_available_login(@profile[:login])
    end
end
