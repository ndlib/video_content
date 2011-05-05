require 'net/http'
require 'mediashelf/active_fedora_helper'
#require "#{RAILS_ROOT}/vendor/pluggins/video_content/app/models/pbcore_xml.rb"

class EventsController < CatalogController
  include Hydra::AssetsControllerHelper
  include Hydra::FileAssetsHelper  
  include Hydra::RepositoryController  
  include MediaShelf::ActiveFedoraHelper
  include Blacklight::SolrHelper
  include WhiteListHelper
  include Blacklight::CatalogHelper
  include ApplicationHelper
  include EventsControllerHelper

  helper :hydra, :metadata, :infusion_view

  #before_filter :initialize_collection, :except=>[:index, :new]
  before_filter :require_solr, :require_fedora, :only=>[:show, :edit, :index, :new, :update, :create, :add, :download]
  def index
    @events = Event.find_by_solr(:all).hits.map{|result| Event.load_instance_from_solr(result["id"])}
  end

  def update
    af_model = retrieve_af_model(params[:content_type])
    unless af_model 
      af_model = Event
    end
    @document = af_model.find(params[:id])
    updater_method_args = prep_updater_method_args(params)
    result = @document.update_indexed_attributes(updater_method_args[:params], updater_method_args[:opts])
    @document.save
    logger.debug("OPTS: #{updater_method_args[:opts].inspect}")
    logger.debug("Result: #{result.inspect}")
    apply_depositor_metadata(@document)
    response = Hash["updated"=>[]]
    last_result_value = ""
    result.each_pair do |field_name,changed_values|
      changed_values.each_pair do |index,value|
	logger.debug("field_name = #{field_name}, index = #{index}, value = #{value}")
        response["updated"] << {"field_name"=>field_name,"index"=>index,"value"=>value} 
        last_result_value = value
      end
    end
    logger.debug("returning #{response.inspect}")

  # If handling submission from jeditable (which will only submit one value at a time), return the value it submitted
    if params.has_key?(:field_id)
      response = last_result_value
    end

    respond_to do |want| 
      want.js {
        render :json=> response
      }
      want.textile {
        if response.kind_of?(Hash)
          response = response.values.first
        end
        render :text=> white_list( RedCloth.new(response, [:sanitize_html]).to_html )
      }
    end
  end

  def new
    content_type = params[:content_type]
    af_model = retrieve_af_model(content_type)
    if af_model
      @asset = create_and_save_event(af_model)
    end
    redirect_to url_for(:action=>"edit", :controller=>"catalog", :label => params[:label], :id=>@asset.pid, :content_type => params[:content_type])
  end

  # Creates new datastream with name COPYRIGHTS for each file upload
  def create
    filemap = Hash.new
    filemap[:file] = params[:Filedata]
    filemap[:filename] = params[:Filename]
    @asset = Event.find(params[:container_id])
    @asset.add_named_datastream("transcripts",filemap)
    @asset.save
    render :nothing => true
#    redirect_to url_for(:action=>"edit", :controller=>"catalog", :id=>@asset.pid, :content_type => params[:content_type])
  end

  # Adds a new node for contributors or production company
  def add
    @asset = Event.load_instance(params[:id])
#    @asset.insert_new_node('creator', {"descMetadata"=>"pbcoreDescription_pbcoreCreator"})
    @asset.insert_new_node(params[:field_type], {"descMetadata"=>params[:text_field]})
    if(params[:field_type].eql?"creator")
      creator = @asset.datastreams["descMetadata"].get_values([:pbcoreDescriptionDocument, :pbcoreCreator])
      @asset.update_indexed_attributes({[:pbcoreDescriptionDocument, {:pbcoreCreator => "#{(creator.size)-1}"}, :creatorRole]=>{0=>"producer"}})
    end
    @asset.save

    url_params = {
      :action       => 'edit',
      :controller   => 'catalog',
      :id           => @asset.pid,
      :content_type => params[:content_type]
    }
    # NOTE anchor tag is defined in edit event view code
    url_params[:anchor] = 'speakers' if params[:content_type] == 'event'
    redirect_to url_for(url_params)
  end

#  def removecreator
#    @asset = Event.load_instance(params[:id])
#    @asset.remove_child('creator', params[:creator_counter])
#    @asset.save
#    redirect_to url_for(:action=>"edit", :controller=>"catalog", :label => params[:label], :id=>@asset.pid)
#  end

  def show  
    show_without_customizations
  end

  def download
    af_model = retrieve_af_model(params[:content_type])
    @file_asset = af_model.find(params[:id])
    send_datastream @file_asset.datastreams_in_memory["#{params[:ds_name]}"]
  end

  def destroy
  end

end
