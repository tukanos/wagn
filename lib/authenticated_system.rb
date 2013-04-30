# -*- encoding : utf-8 -*-
module AuthenticatedSystem
  protected
  def logged_in?
    Account.logged_in?
  end

  # Accesses the current user from the session.
  def current_account_id
    @current_account_id ||= begin
      if card_id = session[:user]
        if User[ card_id ]
          card_id
        else
          session[:user] = nil
        end
      end
    end
  rescue Exception => e
    #warn "except #{e.inspect}, #{e.backtrace*"\n"}"
    session[:user] = nil
    raise e
  end

  # Store the given user in the session.
  def current_account_id= card_id
    @current_account_id = session[:user] = card_id
  end

  #
  def login_required

    # Check if user is logged in
    return true if logged_in?

    # Store current location so that we can redirect back after login
    store_location


    # Call access_denied for an appropriate redirect and stop the filter
    # chain here
    access_denied and return false
  end

  # Redirect as appropriate when an access request fails.
  #
  # The default action is to redirect to the login screen.
  #
  # Override this method in your controllers if you want to have special
  # behavior in case the user is not authorized
  # to access the requested action.  For example, a popup window might
  # simply close itself.
  def access_denied
    wagn_redirect( Wagn::Conf[:base_url] + url_for(:controller=>'account', :action=>'signin') )
  end

  # Store the URI of the current request in the session.
  #
  # We can return to this location by calling #redirect_back_or_default.
  def store_location
    session[:return_to] = request.fullpath
  end

  # Redirect to the URI stored by the most recent store_location call or
  # to the passed default.
  def redirect_back_or_default(default)
    session[:return_to] ? redirect_to(session[:return_to]) :
      (default.nil? ? redirect_to('/') : redirect_to(default))
    session[:return_to] = nil
  end

  # Inclusion hook to make #current_account_id and #logged_in?
  # available as ActionView helper methods.
  def self.included(base)
    super
    base.send :helper_method, :current_account_id, :logged_in?
  end
end
