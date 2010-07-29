# TODO: Make it run on Heroku
class OpenidController < SinglesignonController
  skip_before_filter :login_required

  # Starts the redirect authorization for OpenID
  def start
    @provider = params[:provider]
    @endpoint = params[:endpoint]
    @invitation_token = params[:invitation]

    config = APP_CONFIG['openid_providers'][@provider]
    raise "Provider #{@provider} is missing. Please add the key and secret to the configuration file." unless config

    authenticate_with_open_id(
      @endpoint ? @endpoint : config['endpoint'], 
      :return_to => !@invitation_token ? openid_callback_url({:provider => @provider}) : openid_callback_invitation_url({:provider => @provider, :invitation => @invitation_token}), 
      :required => [
        'http://axschema.org/namePerson/first', 
        'http://axschema.org/namePerson/last', 
        'http://axschema.org/contact/email'])
  end

  def callback
    @provider = params[:provider]
    if params[:invitation]
      @invitation = Invitation.find_by_token(params[:invitation])
      @invitation_token = params[:invitation] if @invitation
    end
    begin

      response = request.env[Rack::OpenID::RESPONSE]
      if response.status != :success
        flash[:notice] = t(:'openid.provider_error', :provider => @provider) 
        return redirect_to login_path
      end

      load_profile(response)
      sso_user      

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
