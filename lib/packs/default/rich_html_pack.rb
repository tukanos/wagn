class Wagn::Renderer::Html
  define_view :show do |args|
    @main_view = args[:view] || params[:view] || params[:home_view]
    
    if ajax_call?
      self.render( @main_view || :open )
    else
      self.render_layout
    end
  end

  define_view :layout, :perms=>:none do |args|
    if @main_content = args.delete( :main_content )
      @card = Card.fetch_or_new '*placeholder'
    end
    
    layout_content = get_layout_content args

    args[:params] = params # EXPLAIN why this is needed
    process_content layout_content, args
  end


  define_view :content do |args| 
    wrap :content, args do
      wrap_content :content, _render_core(args)
    end
  end

  define_view :titled do |args|
    wrap :titled, args do
      _render_title + wrap_content(:titled, _render_core(args))
    end
  end
  
  define_view :title do |args|
    Rails.logger.info "context names = #{@context}"
    t = content_tag :h1, fancy_title, :class=>'card-title', :name_context=>"#{ @context_names.map(&:key)*',' }"
    add_name_context
    t
  end

  define_view :open do |args|
    wrap :open, args do
      %{ 
         #{ _render_title }
         #{ wrap_content :open, _render_open_content(args) } 
         #{ render_comment_box }
         #{ notice }
      }
    end
  end

  define_view :comment_box, :perms=>lambda { |r| 
        r.card.ok?(:comment) ? :comment_box : :blank
      } do |args|
    %{<div class="comment-box nodblclick"> #{
      card_form :comment do |f|
        %{#{f.text_area :comment, :rows=>3 }<br/> #{
        unless Session.logged_in?
          card.comment_author= (session[:comment_author] || params[:comment_author] || "Anonymous") #ENGLISH
          %{<label>My Name is:</label> #{ f.text_field :comment_author }}
        end}
        <input type="submit" value="Comment"/>}
      end}
    </div>}
  end

  define_view :closed do |args|
    wrap :closed, args do
      %{
        <div class="card-header">
          <div class="title-menu">
            #{ link_to( fancy_title, path(:read, :view=>:open), :title=>"open #{card.name}",
              :class=>'title right-arrow slotter', :remote=>true ) }
            #{ page_icon(card.name) } &nbsp;
          </div>
        </div>
        #{ wrap_content :closed, render_closed_content }
      }
    end
  end

  define_view :new, :perms=>:create, :tags=>:unknown_ok do |args|
    type_ready = params[:type] && !card.broken_type
    name_ready = !( card.cardname.blank? || Card.exists?( card.cardname ) )

    cancel = if ajax_call?
      { :class=>'slotter',    :href=>path(:read, :view=>:missing)    }
    else
      { :class=>'redirecter', :href=>Card.path_setting('/*previous') }
    end

    if ajax_call? 
      header_text = card.type_id == Card::DefaultTypeID ? 'Card' : card.type_name
      %{ <h1 class="page-header">New #{header_text}</h1>}
    else '' end +
       
    (wrap :new, args do  
      card_form :create, 'card-form card-new-form', 'main-success'=>'REDIRECT' do |form|
        @form = form
        %{
          <div class="edit-area">          
            #{ hidden_field_tag :success, card.rule(:thanks) || 'TO-CARD' }
            #{ help_text :add_help, :fallback=>:edit_help }
            #{
            case
            when name_ready                  ; _render_title + hidden_field_tag( 'card[name]', card.name )
            when card.rule_card( :autoname ) ; ''
            else                             ; _render_name_editor
            end
            }
            #{ type_ready ? form.hidden_field( :type_id) : _render_type_editor }
            <div class="card-editor editor">#{ edit_slot args }</div>
            <div class="edit-button-area">
              #{ submit_tag 'Submit', :class=>'create-submit-button' }
              #{ button_tag 'Cancel', :type=>'button', :class=>"create-cancel-button #{cancel[:class]}", :href=>cancel[:href] }
            </div>
          </div>
          #{ notice }
        }
      end
    end)
    
  end

  define_view :editor do |args|
    form.text_area :content, :rows=>3, :class=>'tinymce-textarea card-content', :id=>unique_id
  end

  define_view :missing do |args|
    return '' unless card.ok? :create  #this should be moved into ok_view
    #warn "missing #{args.inspect} #{caller[0..10]*"\n"}"
    new_args = { 'card[name]'=>card.name }
    new_args['card[type]'] = args[:type] if args[:type]

    wrap :missing, args do
      link_to raw("Add <strong>#{ showname }</strong>"), path(:new, new_args),
        :class=>'slotter', :remote=>true
    end
  end

###---(  EDIT VIEWS )
  define_view :edit, :perms=>:update, :tags=>:unknown_ok do |args|
    wrap :edit, args do
      %{ 
      #{_render_title }
      #{ help_text :edit_help }
      <div class="card-editor edit-area">
        #{ card_form :update, 'card-form card-edit-form autosave' do |f|
          @form= f
          %{
          <div>#{ edit_slot args }</div>
          <fieldset>
            <div class="button-area">
              #{ submit_tag 'Submit', :class=>'submit-button' }
              #{ button_tag 'Cancel', :class=>'cancel-button slotter', :href=>path(:read), :type=>'button'}
              #{ 
              if !card.new_card?
                #why do we need the data=type here?
                button_tag "Delete", :href=>path(:delete), :type=>'button', 'data-type'=>'html',
                  :class=>'delete-button slotter standard-delete'
              end
              }            
            </div>
          </fieldset>
          }
        end}
      </div>
      #{ notice }
      }
    end
  end

  define_view :name_editor do |args|
    fieldset 'name', (editor_wrap :name do
       raw( name_field form )
    end)
  end

  define_view :type_editor do |args|
    fieldset 'type', (editor_wrap :type do
      type_field :class=>'type-field live-type-field', :href=>path(:new), 'data-remote'=>true
    end)
  end
  
  define_view :edit_name, :perms=>:update do |args|
    wrap :edit_name do
      card_form path(:update, :id=>card.id), 'card-name-form', 'main-success'=>'REDIRECT' do |f|
        %{  
          #{ _render_name_editor}
          #{ hidden_field_tag :success, 'TO-CARD' }
          <div class="confirm-rename">
            WOWSERS?
          </div>
          #{ submit_tag 'Rename', :class=>'edit-name-submit-button' }
          #{ button_tag 'Cancel', :class=>'edit-name-cancel-button slotter', :type=>'button', :href=>path(:edit, :id=>card.id)}
        }
      end
    end
  end
  
  define_view :confirm_rename do |args|
    'WOWSERS!'
  end
  
  #     if !card.errors[:confirmation_required].empty?
  #       card.confirm_rename = card.update_referencers = true
  #       params[:attribute] = 'name'
  #
  #      %{#{if dependents = card.dependents and !dependents.empty?  #ENGLISH below
  #        %{<div class="instruction">
  #          <div>This will change the names of these cards, too:</div>
  #          <ul>#{
  #            dependents.map do |dep|
  #              %{<li>#{ link_to_page dep.name }</li>}
  #            end.join }
  #          </ul>
  #        </div>}
  #      end}#{
  #
  #      if children = card.extended_referencers and !children.empty? #ENGLISH below
  #        %{<h2>References</h2>
  #        <div class="instruction">
  #          <div>Renaming could break old links and inclusions on these cards:</div>
  #          <ul>
  #            #{children.map do |child|
  #              %{<li>#{ link_to_page child.name }</li>}
  #              end.join}
  #          </ul>
  #          <div>You can...
  #            <div class="radio">#{ f.radio_button :update_referencers, 'true' }
  #              <strong>Fix them</strong>: update old references with new name
  #            </div>
  #            <div class="radio">#{ f.radio_button :update_referencers, 'false' }
  #              <strong>Leave them</strong>: let old references point to old name
  #            </div>
  #          </div>
  #        </div>}
  #      end
  #      
  #      }#{
  #      f.hidden_field 'confirm_rename' }}
  #    end

  define_view :edit_type, :perms=>:update do |args|
    %{
    <div class="edit-area edit-type">
      <h2>Change Type</h2> #{
        card_form :update, 'card-edit-type-form' do |f|
          #'main-success'=>'REDIRECT: TO-CARD', # adding this back in would make main cards redirect on cardtype changes
       
          %{ #{ hidden_field_tag :view, :edit }
          #{if card.type_id == Card::CardtypeID and !Card.search(:type_id=>card.card.id).empty? #ENGLISH
            %{<div>Sorry, you can't make this card anything other than a Cardtype so long as there are <strong>#{ card.name }</strong> cards.</div>}
          else
            %{<div>to #{ raw type_field :class=>'type-field edit-type-field' }</div>}
          end}
          <div>
            #{ submit_tag 'Submit', :disable_with=>'Submitting' }
            #{ button_tag 'Cancel', :href=>path(:edit), :type=>'button', :class=>'edit-type-cancel-button slotter' }
          </div>}
       end}
    </div>}
  end

  define_view :edit_in_form, :tags=>:unknown_ok do |args|  #, :perms=>:update
    eform = form_for_multi
    content = content_field eform, :nested=>true
    attribs = %{ class="card-editor RIGHT-#{ card.cardname.tag_name.safe_key }" }
    link_target, help_settings = if card.new_card?
      content += raw( "\n #{ eform.hidden_field :type_id }" )
      [ card.cardname.tag, [:add_help, :fallback => :edit_help] ]
    else
      attribs += %{ card-id="#{card.id}" card-name="#{h card.name}" }
      [ card.name, :edit_help ]
    end
    label = link_to_page fancy_title, link_target
    fieldset label, content, :help=>help_settings, :attribs=>attribs
  end

  define_view :option_account do |args|
    locals = {:slot=>self, :card=>card, :account=>card.to_user }
    %{#{raw( options_submenu(:account) ) }#{

       card_form :update_account do |form|

         %{<table class="fieldset">
           #{if Session.as_id==card.id or card.trait_card(:account).ok?(:update)
              raw option_header( 'Account Details' ) +
                template.render(:partial=>'account/edit',  :locals=>locals)
           end }
        #{ render_option_roles } #{

           if options_need_save
             %{<tr><td colspan="3">#{ submit_tag 'Save Changes' }</td></tr>}
           end}
         </table>}
    end }}
  end

  define_view :option_settings do |args|
    related_sets = card.related_sets
    current_set = params[:current_set] || related_sets[(card.type_id==Card::CardtypeID ? 1 : 0)]  #FIXME - explicit cardtype reference
    set_options = related_sets.map do |set_name| 
      set_card = Card.fetch set_name
      selected = set_card.key == current_set.to_cardname.key ? 'selected="selected"' : ''
      %{<option value="#{ set_card.key }" #{ selected }>#{ set_card.label }</option>}
    end.join
    
    options_submenu(:settings) +

    %{<div class="settings-tab">
      #{ if !related_sets.empty?
        %{ <div class="set-selection">
          #{ form_tag path(:options, :attrib=>:settings), :method=>'get', :remote=>true, :class=>'slotter' }
              <label>Set:</label>
              <select name="current_set" class="set-select">#{ set_options }</select>
          </form>
        </div>}
      end }

      <div class="current-set">
        #{ raw subrenderer( Card.fetch current_set).render_content }
      </div>
  #{
        if Card.toggle(card.rule(:accountable)) && card.trait_card(:account).ok?(:create)
          %{<div class="new-account-link">
          #{ link_to %{Add a sign-in account for "#{card.name}"},
              path(:options, :attrib=>:new_account),
            :class=>'slotter new-account-link', :remote=>true }
          </div>}
         end}
      </div>}
      
      # should be just if !card.trait_card(:account) and Card.new( :name=>"#{card.name}+Card[:account].name").ok?(create)
  end

  define_view(:option_roles) do |args|
    roles = Card.search :type=>Card::RoleID
    # Do we want these as well?  as by type Role?
    #roles = Card.search(:refer_to => {:right=> Card::RolesID})
    traitc = card.trait_card(:roles)
    user_roles = traitc.item_cards(:limit=>0).reject do |x|
      [Card::AnyoneID, Card::AuthID].member? x.id.to_i
    end
#    warn Rails.logger.info("option_roles #{user_roles.inspect}")

    option_content = if traitc.ok? :update
      user_role_ids = user_roles.map &:id
      hidden_field_tag(:save_roles, true) +
      (roles.map do |rolecard|
#        warn Rails.logger.info("option_roles: #{rolecard.inspect}")
        if rolecard && !rolecard.trash
         %{<div style="white-space: nowrap">
           #{ check_box_tag "user_roles[%s]" % rolecard.id, 1, user_role_ids.member?(rolecard.id) ? true : false }
           #{ link_to_page rolecard.name }
         </div>}
        end
      end.compact * "\n").html_safe
    else
      if user_roles.empty?
        'No roles assigned'  # #ENGLISH
      else
        (user_roles.map do |rolecard|
          %{ <div>#{ link_to_page rolecard.name }</div>}
        end * "\n").html_safe
      end
    end

    %{#{ raw option_header( 'User Roles' ) }#{
       option(option_content, :name=>"roles",
      :help=>%{ <span class="small">"#{ link_to_page 'Roles' }" are used to set user permissions</span>}, #ENGLISH
      :label=>"#{card.name}'s Roles",
      :editable=>card.trait_card(:roles).ok?(:update)
    )}}
  end

  define_view :option_new_account do |args|
    %{#{raw( options_submenu(:account) ) }#{
      card_form :create_account do |form|
      #ENGLISH below

        %{<table class="fieldset">
        #{render :partial=>'account/email' }
           <tr><td colspan="3" style><p>
       A password for a new sign-in account will be sent to the above address.
           #{ submit_tag 'Create Account' }
           </p></td></tr>
        </table>}
     end}}
  end

  define_view :changes do |args| 
    load_revisions
    if @revision
      wrap :changes, args do
        %{#{ _render_header unless params['no_changes_header'] }
        <div class="revision-navigation">#{ revision_menu }</div>

        <div class="revision-header">
          <span class="revision-title">#{ @revision.title }</span>
          posted by #{ link_to_page @revision.author.name }
        on #{ format_date(@revision.created_at) } #{
        if !card.drafts.empty?
          %{<p class="autosave-alert">
            This card has an #{ autosave_revision }
          </p>}
        end}#{
        if @show_diff and @revision_number > 1  #ENGLISH
          %{<p class="revision-diff-header">
            <small>
              Showing changes from revision ##{ @revision_number - 1 }:
              <ins class="diffins">Added</ins> | <del class="diffmod">Deleted</del>
            </small>
          </p>}
        end}
        </div>
        <div class="revision content">#{_render_diff}</div>
        <div class="revision-navigation">#{ revision_menu }</div>}
      end
    end
  end

  define_view :diff do |args|
    if @show_diff and @previous_revision
      diff @previous_revision.content, @revision.content
    else
      @revision.content
    end
  end

  define_view :conflict, :error_code=>409 do |args|
    load_revisions
    wrap :errors do |args|
      %{<strong>Conflict!</strong><span class="new-current-revision-id">#{@revision.id}</span>
        <div>#{ link_to_page @revision.author.card.name } has also been making changes.</div>
        <div>Please examine below, resolve above, and re-submit.</div>
        #{wrap(:conflict) { |args| _render_diff } } }
    end
  end

  define_view :delete do |args|
    wrap :delete, args do
    %{#{ _render_header}
    #{card_form :delete, '', 'data-type'=>'html', 'main-success'=>'REDIRECT: TO-PREVIOUS' do |f|
    
      %{#{ hidden_field_tag 'confirm_destroy', 'true' }#{
        hidden_field_tag 'success', "TEXT: #{card.name} deleted" }

    <div class="content open-content">
      <p>Really remove #{ raw link_to_page( card.name ) }?</p>#{
       if dependents = card.dependents and !dependents.empty? #ENGLISH ^
        %{<p>That would mean removing all these cards, too:</p>
        <ul>
          #{ dependents.map do |dep|
            %{<li>#{ link_to_page dep.name }</li>}
          end.join }
        </ul>}
       end}
       #{ submit_tag 'Yes do it', :class=>'delete-submit-button' }
       #{ button_tag 'Cancel', :class=>'delete-cancel-button slotter', :type=>'button', :href=>path(:read) }
       #{ notice }
    </div>
      }
    end}}
    end
  end

  define_view :change do |args|
    wrap :change, args do
      %{#{link_to_page card.name, nil, :class=>'change-card'} #{
       if rev = card.current_revision and !rev.new_record?
         # this check should be unnecessary once we fix search result bug
         %{<span class="last-update"> #{

           case card.updated_at.to_s
             when card.created_at.to_s; 'added'
             when rev.created_at.to_s;  link_to('edited', path(:changes), :class=>'last-edited')
             else; 'updated'
           end} #{

            time_ago_in_words card.updated_at } ago by #{ #ENGLISH
            link_to_page card.updater.name, nil, :class=>'last-editor'}
          </span>}
       end }
       <br style="clear:both"/>}
    end
  end

  define_view :header do |args|
    add_name_context
    %{<div class="card-header">
       #{ menu }
       <div class="title-menu">
         #{ link_to fancy_title, path(:read, :view=>:closed),
            :title => "close #{card.name}", 
            :class => "line-link title down-arrow slotter", 
            :remote => true 
          }
         #{ card.type_id==Card::BasicID ? '' : %{<span class="cardtype">#{ link_to_page card.type_name }</span>} }
         #{ page_icon(card.name) } &nbsp;
       </div>
    </div>}
  end

  define_view :errors, :perms=>:none do |args|
    wrap :errors, args do
      %{ <h2>Can't save "#{card.name}".</h2> } +
      card.errors.map { |attrib, msg| "<div>#{attrib.upcase}: #{msg}</div>" } * ''
    end
  end

  define_view :not_found do |args| #ug.  bad name.

    sign_in_or_up_links = Session.logged_in? ? '' :
      %{
      <div>
        #{link_to "Sign In", :controller=>'account', :action=>'signin'} or
        #{link_to 'Sign Up', :controller=>'account', :action=>'signup'} to create it.
      </div>
      }
    %{ <h1 class="page-header">Missing Card</h1> } +
    wrap( :not_found, args ) do # ENGLISH 
      %{<div class="content instruction">
          <div>There's no card named <strong>#{card.name}</strong>.</div>
          #{sign_in_or_up_links}
        </div>}
    end
  end


  define_view :watch, :tags=>:unknown_ok, :perms=> lambda { |r| 
        !Session.logged_in? || r.card.new_card? ? :blank : :watch 
      } do |args|
        
    wrap :watch do
      if card.watching_type?
        watching_type_cards
      else
        link_args = if card.watching?
          ["unwatch", :off, "stop sending emails about changes to #{card.cardname}"]
        else
          ["watch", :on, "send emails about changes to #{card.cardname}"]
        end
        watch_link *link_args
      end
    end
  end
  
  def watching_type_cards
    "watching #{ link_to_page card.type_name } cards"
  end

  def watch_link text, toggle, title, extra={}
    link_to "#{text}", path(:watch, :toggle=>toggle), 
      {:class=>"watch-toggle watch-toggle-#{toggle} slotter", :title=>title, :remote=>true, :method=>'post'}.merge(extra)
  end
  
  define_view :denial do |args|
    task = args[:denied_task] || params[:action]
    if !focal?
      %{<span class="denied"><!-- Sorry, you don't have permission to #{task} this card --></span>}
    else
      wrap :denial, args do #ENGLISH below
        %{#{ _render_header } 
          <div id="denied" class="instruction open-content">
            <h1>Ooo.  Sorry, but...</h1>
  
        
         #{ if task != :read && Wagn::Conf[:read_only]
              "<div>We are currently in read-only mode.  Please try again later.</div>"
            else
              %{<div>#{
            
              if !Session.logged_in?
               %{You have to #{ link_to "sign in", :controller=>'account', :action=>'signin' }}
              else
               "You need permission"
              end} to #{task} this card#{": <strong>#{card.name}</strong>" if card.name && !card.name.blank? }.
              </div>
             #{
  
              if !Session.logged_in? && Card.new(:type_id=>Card::AccountRequestID).ok?(:create)
                %{<p>#{ link_to 'Sign up for a new account', :controller=>'account', :action=>'signup' }.</p>}
              end }}
            end   }
          </div>
          }
      end
    end
  end
  
  
  define_view :server_error do |args|
    %{
    <body>
      <div class="dialog">
        <h1>Wagn Hitch :(</h1>
        <p>Server Error. Yuck, sorry about that.</p>
        <p><a href="http://www.wagn.org/new/Support_Ticket">Add a support ticket</a>
            to tell us more and follow the fix.</p>
      </div>
    </body>
    }
  end
  

  
  def card_form *opts
    form_for( card, form_opts(*opts) ) { |form| yield form }
  end

  def form_opts url, classes='', other_html={}
    url = path(url) if Symbol===url
    opts = { :url=>url, :remote=>true, :html=>other_html }
    opts[:html][:class] = classes + ' slotter'
    opts[:html][:recaptcha] = 'on' if Wagn::Conf[:recaptcha_on] && Card.toggle( card.rule(:captcha) )
    opts
  end
  
  private
  
  def editor_wrap type
    content_tag( :div, :class=>"editor #{type}-editor" ) { yield }
  end
    
  def fieldset title, content, opts={}
    %{
      <fieldset #{ opts[:attribs] }>
        <legend>
          <h2>#{ title }</h2>
          #{ help_text *opts[:help] }
        </legend>
        #{ content }
      </fieldset>
    }
  end
  
  def help_text *opts
    Rails.logger.info "help text called with args #{opts} for #{card.name}"
    text = case opts[0]
      when Symbol
        if help_card = card.rule_card( *opts )
          with_inclusion_mode :normal do
            subrenderer( help_card ).render_core
          end
        end
      when String
        opts[0]
      end
    %{<div class="instruction">#{raw text}</div>} if text
  end

  def fancy_title name=nil
    name ||= showname
    title = name.to_cardname.parts.join %{<span class="joint">+</span>}
    raw title
  end

  def page_icon cardname
    link_to_page '&nbsp;'.html_safe, cardname, {:class=>'page-icon', :title=>"Go to: #{cardname.to_s}"}
  end

  def load_revisions
    @revision_number = (params[:rev] || (card.revisions.count - card.drafts.length)).to_i
    @revision = card.revisions[@revision_number - 1]
    @previous_revision = @revision ? card.previous_revision( @revision.id ) : nil
    @show_diff = (params[:mode] != 'false')
  end

  #FIXME - don't delete until broken type errors are handled!

#  def new_instruction
#    if card.broken_type
#            %{<div class="error" id="no-cardtype-error">
#              Oops! There's no <strong>card type</strong> called "<strong>#{ card.broken_type }</strong>".
#            </div>}
#          end }
#    i.blank? ? '' : %{<div class="instruction new-instruction"> #{ i } </div>}
#  end


end

