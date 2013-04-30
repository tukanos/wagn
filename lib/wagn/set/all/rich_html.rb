# -*- encoding : utf-8 -*-
module Wagn
  module Set::All::RichHtml
    include Sets

    format :html

    define_view :show do |args|
      @main_view = args[:view] || args[:home_view]

      if ajax_call?
        view = @main_view || :open
        self.render view, args
      else
        self.render_layout args
      end
    end

    define_view :layout, :perms=>:none do |args|
      if @main_content = args.delete( :main_content )
        @card = Card.fetch '*placeholder', :new=>{}
      end

      layout_content = get_layout_content args

      args[:params] = params # EXPLAIN why this is needed
      process_content layout_content, args
    end
  
    define_view :content do |args|
      wrap :content, args do
        %{
          #{ optional_render :menu, args, default_hidden=true }
          #{ wrap_content( :content ) { _render_core args }   }
        }
      end
    end

    define_view :titled, :tags=>:comment do |args|
      wrap :titled, args do
        %{
          #{ _render_header args.merge( :menu_default_hidden=>true ) }
          #{ wrap_content( :titled, :body=>true ) { _render_core args } }
          #{ optional_render :comment_box, args }
        }
      end
    end
    
    define_view :labeled do |args|
      wrap :labeled, args do
        %{
          #{ _optional_render :menu, args }
          
          <label>
            #{ _render_title args }
          </label>
          #{
            wrap_content :titled do
              _render_closed_content args
            end
          }
        }
      end
    end
  
    define_view :title do |args|
      title = content_tag :h1, fancy_title( args[:title] ), :class=>'card-title'
      title = _optional_render( :title_link, args.merge( :title_ready=>title ), default_hidden=true ) || title
      add_name_context
      title
    end
    
    define_view :title_link do |args|
      link_to_page (args[:title_ready] || showname(args[:title]) ), card.name
    end
    
  

    define_view :open, :tags=>:comment do |args|
      args[:toggler] = link_to '', path( :view=>:closed ),
        :remote => true,
        :title  => "close #{card.name}",
        :class  => "close-icon ui-icon ui-icon-circle-triangle-s toggler slotter nodblclick"
        
      wrap :open, args.merge(:frame=>true) do
        %{
           #{ _render_header args }
           #{ wrap_content( :open, :body=>true ) { _render_open_content args } }
           #{ optional_render :comment_box, args }
        }
      end
    end

    define_view :header do |args|
      %{
        <div class="card-header">
          #{ args.delete :toggler }
          #{ _render_title args }
          #{ _optional_render :menu, args, args[:menu_default_hidden] || false }
          #{ optional_render :help, args.merge( :setting => :help ), args[:help_default_hidden].nil? ? true : false }
        </div>
        
      }
    end
  
    define_view :menu, :tags=>:unknown_ok do |args|
      disc_tagname = Card.fetch(:discussion, :skip_modules=>true).cardname
      disc_card = unless card.junction? && card.cardname.tag_name.key == disc_tagname.key
        Card.fetch "#{card.name}+#{disc_tagname}", :skip_virtual=>true, :skip_modules=>true, :new=>{}
      end
      
      @menu_vars = {
        :self         => card.name,
        :type         => card.type_name,
        :structure    => card.hard_template && card.template.ok?(:update) && card.template.name,
        :discuss      => disc_card && disc_card.ok?( disc_card.new_card? ? :comment : :read),
        :piecenames   => card.junction? && card.cardname.piece_names[0..-2].map { |n| { :item=>n } },
        :related_sets => card.related_sets.map { |name,label| { :text=>label.gsub('%','%%'), :path_opts=>{ :current_set => name } } }
          #should generalize percent thing.  this is because sprintf is run on all "text" values.
      }
      if card.real?
        @menu_vars.merge!({
          :edit      => card.ok?(:update),
          :account   => card.account && card.update_account_ok?,
          :watch     => Account.logged_in? && render_watch,
          :creator   => card.creator.name,
          :updater   => card.updater.name,
          :delete    => card.ok?(:delete) && link_to( 'delete', path(:action=>:delete),
            :class => 'slotter standard-delete', :remote => true, :'data-confirm' => "Are you sure you want to delete #{card.name}?"
          )
        })
      end
    
      %{
        <div class="card-menu-link">
          #{ _render_menu_link }
          <ul class="card-menu">
            #{ build_menu_items default_menu }
          </ul>
        </div>
      }
    end

    define_view :menu_link do |args|
      '<a class="ui-icon ui-icon-gear"></a>'
    end
  
    define_view :type do |args|
      klasses = ['cardtype']
      klasses << 'default-type' if card.type_id==Card::DefaultTypeID ? " default-type" : ''
      link_to_page card.type_name, nil, :class=>klasses
    end

    define_view :closed do |args|
      args[:toggler] = link_to '', path( :view=>:open ),
        :remote => true,
        :title => "open #{card.name}",
        :class => "open-icon ui-icon ui-icon-circle-triangle-e toggler slotter nodblclick"
      wrap :closed, args do
        %{
          #{ render_header args }
          #{ wrap_content( :closed ) { _render_closed_content args } }
        }
      end
    end
  
  
    define_view( :comment_box, :denial=>:blank, :tags=>:unknown_ok, :perms=>lambda { |r| r.card.ok? :comment } ) do |args|
      
      %{<div class="comment-box nodblclick"> #{
        card_form :update do |f|
          %{#{f.text_area :comment, :rows=>3 }<br/> #{
          unless Account.logged_in?
            card.comment_author= (session[:comment_author] || params[:comment_author] || "Anonymous") #ENGLISH
            %{<label>My Name is:</label> #{ f.text_field :comment_author }}
          end}
          <input type="submit" value="Comment"/>}
        end}
      </div>}
    end



    define_view :new, :perms=>:create, :tags=>:unknown_ok do |args|
      name_ready = !card.cardname.blank? && !Card.exists?( card.cardname )
      prompt_for_name = !name_ready && !card.rule_card( :autoname )

      prompt_for_type = if !params[:type]
        ( main? || card.simple? || card.is_template? ) and
          Card.new( :type_id=>card.type_id ).ok? :create #otherwise current type won't be on menu
      end

      cancel = if main?
        { :class=>'redirecter', :href=>Card.path_setting('/*previous') }
      else        
        { :class=>'slotter',    :href=>path( :view=>:missing         ) }
      end
      
              
      (wrap :new, args.merge(:frame=>true) do  
        card_form :create, 'card-form card-new-form', 'main-success'=>'REDIRECT' do |form|
          @form = form
          %{
            #{ hidden_field_tag :success, card.rule(:thanks) || '_self' }
            <div class="card-header">          
              #{
                if name_ready
                  _render_title(args) + hidden_field_tag( 'card[name]', card.name )
                else
                  args[:title] ||= "New #{ card.type_name unless card.type_id == Card::DefaultTypeID }"
                  _render_title args
                end
              }
              #{ _render_help :setting => :add_help }
              
            </div>
            
            #{ _render_name_editor if prompt_for_name }

            <div class="card-body">
              #{ prompt_for_type ? _render_type_menu : form.hidden_field( :type_id ) }
            
              <div class="card-editor editor">#{ edit_slot args.merge( :label => prompt_for_name || prompt_for_type ) }</div>
              <fieldset>
                <div class="button-area">
                  #{ submit_tag 'Submit', :class=>'create-submit-button', :disable_with=>'Submitting' }
                  #{ button_tag 'Cancel', :type=>'button', :class=>"create-cancel-button #{cancel[:class]}", :href=>cancel[:href] }
                </div>
              </fieldset>
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
      new_args = { :view=>:new, 'card[name]'=>card.name }
      new_args['card[type]'] = args[:type] if args[:type]

      wrap :missing, args do
        link_to raw("Add #{ fancy_title args[:title] }"), path(new_args),
          :class=>"slotter missing-#{ args[:denied_view] || args[:home_view]}", :remote=>true
      end
    end

  ###---(  EDIT VIEWS )
    define_view :edit, :perms=>:update, :tags=>:unknown_ok do |args|
      wrap :edit, args.merge(:frame=>true) do
        %{
          #{ _render_header :help_default_hidden=>false }
          #{ wrap_content :edit, :body=>true, :class=>'card-editor' do
            card_form :update, 'card-form card-edit-form autosave' do |f|
              @form= f
              %{
                <div>#{ edit_slot args }</div>
                <fieldset>
                  <div class="button-area">
                    #{ submit_tag 'Submit', :class=>'submit-button' }
                    #{ button_tag 'Cancel', :class=>'cancel-button slotter', :href=>path, :type=>'button' }
                  </div>
                </fieldset>
                #{ notice }
              }
            end
          end
          }
        }
      end
    end

    define_view :name_editor do |args|
      fieldset 'name', raw( name_field form ), :editor=>'name', :help=>args[:help]
    end

    define_view :edit_name, :perms=>:update do |args|
      card.update_referencers = false
      referers = card.extended_referencers
      dependents = card.dependents
    
      wrap :edit_name, args.merge(:frame=>true) do
        _render_header +
        wrap_content( :edit_name, :body=>true, :class=>'card-editor' ) do
          card_form( path(:action=>:update, :id=>card.id), 'card-name-form', 'main-success'=>'REDIRECT' ) do |f|
            @form = f
            %{  
              #{ _render_name_editor}  
              #{ f.hidden_field :update_referencers, :class=>'update_referencers'   }
              #{ hidden_field_tag :success, '_self'  }
              #{ hidden_field_tag :old_name, card.name }
              #{ hidden_field_tag :referers, referers.size }
              <div class="confirm-rename hidden">
                <h1>Are you sure you want to rename <em>#{card.name}</em>?</h1>
                #{ %{ <h2>This change will...</h2> } if referers.any? || dependents.any? }
                <ul>
                  #{ %{<li>automatically alter #{ dependents.size } related name(s). } if dependents.any? }
                  #{ %{<li>affect at least #{referers.size} reference(s) to "#{card.name}".} if referers.any? }
                </ul>
                #{ %{<p>You may choose to <em>ignore or update</em> the references.</p>} if referers.any? }  
              </div>
              <fieldset>
                <div class="button-area">
                  #{ submit_tag 'Rename and Update', :class=>'renamer-updater hidden' }
                  #{ submit_tag 'Rename', :class=>'renamer' }
                  #{ button_tag 'Cancel', :class=>'edit-name-cancel-button slotter', :type=>'button', :href=>path(:view=>:edit, :id=>card.id)}
                </div>
              </fieldset>
            }
          end
        end
      end
    end

    define_view :type_menu do |args|
      field = if args[:variety] == :edit
        type_field :class=>'type-field edit-type-field'
      else
        type_field :class=>"type-field live-type-field", :href=>path(:view=>:new), 'data-remote'=>true
      end
      fieldset 'type', field, :editor => 'type', :attribs => { :class=>'type-fieldset'}
    end

    define_view :edit_type, :perms=>:update do |args|
      wrap :edit_type, args.merge(:frame=>true) do
        _render_header +
        wrap_content( :edit_type, :body=>true, :class=>'card-editor' ) do
          card_form( :update, 'card-edit-type-form' ) do |f|
            #'main-success'=>'REDIRECT: _self', # adding this back in would make main cards redirect on cardtype changes
            %{ 
              #{ hidden_field_tag :view, :edit }
              #{if card.type_id == Card::CardtypeID and !Card.search(:type_id=>card.id).empty? #ENGLISH
                %{<div>Sorry, you can't make this card anything other than a Cardtype so long as there are <strong>#{ card.name }</strong> cards.</div>}
              else
                _render_type_menu :variety=>:edit #FIXME dislike this api -ef
              end}
              <fieldset>
                <div class="button-area">              
                  #{ submit_tag 'Submit', :disable_with=>'Submitting' }
                  #{ button_tag 'Cancel', :href=>path(:view=>:edit), :type=>'button', :class=>'edit-type-cancel-button slotter' }
                </div>
              </fieldset>
            }
          end
        end
      end
    end

    define_view :edit_in_form, :perms=>:update, :tags=>:unknown_ok do |args|
      eform = form_for_multi
      content = content_field eform, :nested=>true
      opts = {
        :editor  => 'content',
        :attribs => { :class=> "card-editor RIGHT-#{ card.cardname.tag_name.safe_key }" }
      }
      if card.new_card?
        content += raw( "\n #{ eform.hidden_field :type_id }" )
        opts[:help] = { :setting => :add_help }
      else
        opts[:attribs].merge! :card_id=>card.id, :card_name=>(h card.name)
        opts[:help] = { :setting => :help }
      end
      fieldset fancy_title, content, opts
    end

  
    define_view :options do |args|
      current_set = Card.fetch( params[:current_set] || card.related_sets[0][0] )

      wrap :options, args.merge(:frame=>true) do
        %{
          #{ _render_header }
          <div class="card-body">
            #{ subrenderer( current_set ).render_content }

            #{ if card.accountable?
                %{<div class="new-account-link">
                #{ link_to %{Add a sign-in account for "#{card.name}"}, path(:view=>:new_account),
                     :class=>'slotter new-account-link', :remote=>true }
                </div>}
               end
            }
          </div>
        }
      end
    end
    
    
    define_view :account, :perms=> lambda { |r| r.card.update_account_ok? } do |args|

      locals = {:slot=>self, :card=>card, :account=>card.account }
      wrap :options, args.merge(:frame=>true) do
        %{ #{ _render_header }
          <div class="card-body">
            #{
              card_form :update_account, '', 'notify-success'=>'account details updated' do |form|
                %{
                  #{ hidden_field_tag 'success[id]', '_self' }
                  #{ hidden_field_tag 'success[view]', 'account' }
                  #{ render_account_details }
                  #{ render_account_roles   }
                  <fieldset><div class="button-area">#{ submit_tag 'Save Changes' }</div></fieldset>
                }
              end
            }
          </div>
        }
      end
    end


    define_view :account_details, :perms=>lambda { |r| r.card.update_account_ok? } do |args|
      account = args[:account] || card.account
      
      %{
        #{ fieldset :email, text_field( :account, :email, :autocomplete => :off, :value=>account.email ) }
        #{ fieldset :password, password_field( :account, :password ), :help=>(args[:setup] ? nil : 'no change if blank') }
        #{ fieldset 'confirm password', password_field( :account, :password_confirmation ) }
        #{ 
          if !args[:setup] && Account.user.id != account.id 
            fieldset :block, check_box_tag( 'account[blocked]', '1', account.blocked? ), :help=>'prevents sign-ins'
          end
        }
      }
      
    end
    
    define_view :account_roles, :perms=>lambda { |r| 
          r.card.fetch( :trait => :roles, :new=>{} ).ok? :read
        } do |args|
          
      roles = Card.search( :type=>Card::RoleID, :limit=>0 ).reject do |x|
        [Card::AnyoneID, Card::AuthID].member? x.id.to_i
      end

      traitc = card.fetch :trait => :roles, :new=>{}
      user_roles = traitc.item_cards :limit=>0

      option_content = if traitc.ok? :update
        user_role_ids = user_roles.map &:id
        hidden_field_tag(:save_roles, true) +
        (roles.map do |rolecard|
          if rolecard && !rolecard.trash
           %{<div style="white-space: nowrap">
             #{ check_box_tag "account_roles[%s]" % rolecard.id, 1, user_role_ids.member?(rolecard.id) ? true : false }
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

      fieldset :roles, option_content
    end

    define_view :new_account, :perms=> lambda { |r| r.card.accountable? } do |args|
      wrap :new_account, args.merge(:frame=>true) do
        %{
          #{ _render_header }
          #{
            card_form :create_account do |form|
              %{
                #{ hidden_field_tag 'success[id]', '_self' }
                #{ hidden_field_tag 'success[view]', 'account' }
                #{ fieldset :email, text_field( :account, :email ), :help=>'A password will be sent to the above address.' }
                <fieldset><div class="button-area">#{ submit_tag 'Create Account' }</div></fieldset>
              }
            end
          }
        }
      end
    end
    
    define_view :related do |args|
      if rparams = params[:related]
        rcardname = rparams[:name].to_name.to_absolute_name( card.cardname)
        rcard = Card.fetch rcardname, :new=>{}
        rview = rparams[:view] || :titled        
        show = 'menu,help'
        show += ',comment_box' if rparams[:name] == '+discussion'

        wrap :related, args.merge(:frame=>true) do
          %{
            #{ _render_header }
            <div class="card-body">
              #{ process_inclusion rcard, :view=>rview, :show=>show }
            </div>
          }
        end
      end
    end

    define_view :changes do |args|
      load_revisions
      if @revision
        wrap :changes, args.merge(:frame=>true) do
          %{#{ _render_header }
            <div class="revision-header">
              <span class="revision-title">#{ @revision.title }</span>
              posted by #{ link_to_page @revision.creator.name }
              on #{ format_date(@revision.created_at) } #{
              if !card.drafts.empty?
                %{<div class="autosave-alert">
                  This card has an #{ autosave_revision }
                </div>}
              end}#{
              if @show_diff and @revision_number > 1  #ENGLISH
                %{<div class="revision-diff-header">
                  <small>
                    Showing changes from revision ##{ @revision_number - 1 }:
                    <ins class="diffins">Added</ins> | <del class="diffmod">Deleted</del>
                  </small>
                </div>}
              end}
            </div>
            <div class="revision-navigation">#{ revision_menu }</div>
            #{ wrap_content( :revision, :body=>true ) { _render_diff } }
          }
        end
      end
    end

    define_view :help, :tags=>:unknown_ok do |args|
      text = if args[:text]
        args[:text]
      elsif setting = args[:setting]
        setting = [ :add_help, :fallback => :help ] if setting == :add_help
        if help_card = card.rule_card( *setting ) and help_card.ok? :read
          with_inclusion_mode :normal do
            _final_core args.merge( :structure=>help_card.name )
          end
        end
      end
      %{<div class="instruction">#{raw text}</div>} if text
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
          <div>#{ link_to_page @revision.creator.name } has also been making changes.</div>
          <div>Please examine below, resolve above, and re-submit.</div>
          #{wrap(:conflict) { |args| _render_diff } } }
      end
    end

    define_view :change do |args|
      wrap :change, args do
        %{
          #{link_to_page card.name, nil, :class=>'change-card'}
          #{ _optional_render :menu, args, default_hidden=true }
          #{
          if rev = card.current_revision and !rev.new_record?
            # this check should be unnecessary once we fix search result bug
            %{<span class="last-update"> #{

              case card.updated_at.to_s
                when card.created_at.to_s; 'added'
                when rev.created_at.to_s;  link_to('edited', path(:view=>:changes), :class=>'last-edited', :rel=>'nofollow')
                else; 'updated'
              end} #{
         
               time_ago_in_words card.updated_at } ago by #{ #ENGLISH
               link_to_page card.updater.name, nil, :class=>'last-editor'}
             </span>}
          end
          }
        }
      end
    end

    define_view :errors, :perms=>:none do |args|
      #Rails.logger.debug "errors #{args.inspect}, #{card.inspect}, #{caller[0..3]*", "}"
      wrap :errors, args do
        %{ <h2>Problems #{%{ with <em>#{card.name}</em>} unless card.name.blank?}</h2> } +
        card.errors.map { |attrib, msg| "<div>#{attrib.to_s.upcase}: #{msg}</div>" } * ''
      end
    end

    define_view :not_found do |args| #ug.  bad name.
      sign_in_or_up_links = if !Account.logged_in?
        %{<div>
          #{link_to "Sign In", :controller=>'account', :action=>'signin'} or
          #{link_to 'Sign Up', :controller=>'account', :action=>'signup'} to create it.
         </div>}
      end
    
      wrap( :not_found, args.merge(:frame=>true) ) do # ENGLISH
        %{
          <div class="card-header"><h1>Not Found</h1></div>
          <div class="card-body">
            <h2>Could not find #{card.name.present? ? "<em>#{card.name}</em>" : 'the card requested'}.</h2>
            #{sign_in_or_up_links}
          </div>}
      end
    end

    define_view :denial do |args|
      to_task = if task = args[:denied_task]
        %{to #{task} this card#{ ": <strong>#{card.name}</strong>" if card.name && !card.name.blank? }.}
      else
        'to do that.'
      end
      if !focal?
        %{<span class="denied"><!-- Sorry, you don't have permission #{to_task} --></span>}
      else
        wrap :denial, args.merge(:frame=>true) do #ENGLISH below
          %{
          #{ _render_header }
          <div class="card-body">
            <h1>Ooo.  Sorry, but...</h1>
            #{
            if task != :read && Wagn::Conf[:read_only]
              "<div>We are currently in read-only mode.  Please try again later.</div>"
            else
              if Account.logged_in?
                %{<div>You need permission #{to_task}</div> }
              else
                %{<div>You have to #{ link_to "sign in", wagn_url("/account/signin") } #{to_task}</div> 
                #{ 
                if Card.new(:type_id=>Card::AccountRequestID).ok? :create
                  %{<div>#{ link_to 'Sign up for a new account', wagn_url("/account/signup") }.</div>}                    
                end 
                }}
              end
            end}
          </div>}
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
  
    define_view :watch, :tags=>:unknown_ok, :denial=>:blank,
      :perms=> lambda { |r| Account.logged_in? && !r.card.new_card? } do |args|
        
      wrap :watch do
        if card.watching_type?
          watching_type_cards
        else
          link_args = if card.watching?
            ["following", :off, "stop sending emails about changes to #{card.cardname}", { :hover_content=> 'unfollow' } ]
          else
            ["follow", :on, "send emails about changes to #{card.cardname}" ]
          end
          watch_link *link_args
        end
      end
    end
    
  end  
  
  class Renderer::Html < Renderer
    
    def build_menu_items array
      
      array.map do |h|
        add_li_tag = true
        h = h.clone if Hash===h
        if !h[:if] or @menu_vars[ h[:if] ]
          h[:text] = h[:text] % @menu_vars if h[:text]
          link = case
            when h[:plain]
              "<a>#{h[:plain]}</a>"
            when h[:link]
              menu_subs h[:link]
            when h[:page]
              next unless h[:page] = menu_subs( h[:page] )
              link_to_page (raw("#{h[:text] || h[:page]} &crarr;")), h[:page]
            when h[:list]
              items = []
              h[:list].each do |k1,v1| # piecenames, {pages=>itmes}
                items = menu_subs(k1).map do |item_val| #[names].each do |name|
                  menu_item = v1.clone
                  menu_item.each do |k2, v2| # | :page, :item|
                    menu_item[k2] = item_val[v2] if item_val.has_key?(v2)
                  end
                  menu_item
                end
              end
              add_li_tag = false
              build_menu_items items
            else
              if h[:related]
                h[:related] = if Symbol === h[:related]
                  h[:text] ||= h[:related].to_s.gsub '_', ' '
                  { :name => '+' + Card.fetch( h[:related], :skip_modules=>true ).name }
                else
                  h2 = h[:related].clone
                  h2[:name] = menu_subs h2[:name]
                  h2
                end
                h[:view] = :related
                h[:path_opts] ||= {}
                h[:path_opts].merge! :related=>h[:related]
              end                
                
              if h[:view]
                link_to_view (h[:text] || h[:view]), h[:view], :class=>'slotter', :path_opts=>h[:path_opts]
              else
                raise "bad menu item"
              end
            end
          sub = h[:sub] && "\n<ul>\n#{build_menu_items h[:sub]}\n</ul>\n"
          add_li_tag ? "<li>#{link} #{sub}</li>" : link
        end
      end.flatten.compact * "\n"
    end
    
    def menu_subs key
      Symbol===key ? @menu_vars[key] : key
    end
    
    def watching_type_cards
      %{<div class="faint">(following)</div>} #yuck
    end

    def watch_link text, toggle, title, extra={}
      link_to "#{text}", path(:action=>:watch, :toggle=>toggle), 
        {:class=>"watch-toggle watch-toggle-#{toggle} slotter", :title=>title, :remote=>true, :method=>'post'}.merge(extra)
    end
  end  
end

