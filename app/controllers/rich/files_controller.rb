module Rich
  class FilesController < ApplicationController

    before_action :authenticate_rich_user
    before_action :set_rich_file, only: [:show, :update, :destroy]

    layout "rich/application"

    def index
      @type = params[:type]

      @items = case @type
      when 'file'
        RichFile.files
      when 'image'
        RichFile.images
      when 'video'
        RichFile.videos
      end

      if params[:scoped] == 'true'
        @items = @items.where("owner_type = ? AND owner_id = ?", params[:scope_type], params[:scope_id])
      end

      searchRoute = false
      if params[:search].present?
        # @items = @items.where('rich_file_file_name ILIKE ?', "%#{ params[:search] }%") #original-search
        searchString = params[:search]
        searchString = searchString.strip
        searchList = Array.new
        Rails.logger.info "SEARCH MANY"
        if searchString.include? ","
          searchList_in = searchString.split(",")
          searchList_in.each_with_index do |s, idx|
            s = s.strip
            if !s.empty? 
              searchList.push("%#{s}%")
            end
          end
          Rails.logger.info searchList
          if searchList.length > 0
            @items = @items.where('rich_file_file_name ILIKE ANY ( array[?] )', searchList)
            searchRoute = true
          end
        else
          if !searchString.empty? 
            @items = @items.where('rich_file_file_name ILIKE ?', "%#{ searchString }%")
            searchRoute = true
          end
        end
      end

      if params[:searchtags].present?
        searchString = params[:searchtags]
        searchString = searchString.strip
        searchList = Array.new
        Rails.logger.info "SEARCH MANY TAGS"
        if searchString.include? ","
          searchList_in = searchString.split(",")
          searchList_in.each_with_index do |s, idx|
            s = s.strip
            if !s.empty? 
              searchList.push("%#{s}%")
            end
          end
          Rails.logger.info searchList
          if searchList.length > 0
            @items = @items.where('tags ILIKE ANY ( array[?] )', searchList)
            searchRoute = true
          end
        else
          if !searchString.empty? 
            @items = @items.where('tags ILIKE ?', "%#{ searchString }%")
            searchRoute = true
          end
        end
      end

      if params[:alpha].present?
        @items = @items.order("rich_file_file_name ASC")
      else
        @items = @items.order("created_at DESC")
      end

      if !searchRoute # paginate if ALL files
        @items = @items.page params[:page]
      end

      # stub for new file
      @rich_asset = RichFile.new

      respond_to do |format|
        format.html
        format.js
      end

    end

    def show
      # show is used to retrieve single files through XHR requests after a file has been uploaded

      if(params[:id])
        # list all files
        @file = @rich_file
        render :layout => true
      else
        render :text => "File not found"
      end

    end

    def create
      # use the file from Rack Raw Upload
      file_params = params.fetch(:rich_file, {}).fetch(:rich_file, nil) || (params[:qqfile].is_a?(ActionDispatch::Http::UploadedFile) ? params[:qqfile] : params[:file] )

      # simplified_type is only passed through via JS
      # if using the legacy uploader, we need to determine file type via ActionDispatch::Http::UploadedFile#content_type so the validations on @file do not fail
      sim_file_type = if params[:simplified_type].present?
        params[:simplified_type]
      elsif file_params.content_type =~ /image/i
        'image'
      elsif file_params.content_type =~ /video/i
        'video'
      elsif file_params.content_type =~ /file/i
        'file'
      else
        'file'
      end

      @file = RichFile.new(simplified_type: sim_file_type)

      if(params[:scoped] == 'true')
        @file.owner_type = params[:scope_type]
        @file.owner_id = params[:scope_id].to_i
      end

      if(file_params)
        file_params.content_type = Mime::Type.lookup_by_extension(file_params.try(:original_filename).try(:split, '.').try(:last).try(:to_sym) || params[:file] || params[:qqfile])
        @file.rich_file = file_params
      end

      if @file.save
        response = { success: true, rich_id: @file.id }
      else
        response = { success: false,
                     error: "Could not upload your file:\n- "+@file.errors.to_a[-1].to_s,
                     params: params.inspect }
      end

      render json: response, content_type: "text/html"
    end

    def update
      new_filename_without_extension = ""
      if params[:filename] != nil
        new_filename_without_extension = params[:filename].parameterize
      end     
      if params[:inputfilename] != nil
        new_filename_without_extension = params[:inputfilename]
      end
      tags = params[:image_tags]
      if new_filename_without_extension.present?
        new_filename = @rich_file.rename!(new_filename_without_extension)
        render :json => { :success => true, :filename => new_filename, :uris => @rich_file.uri_cache }
      elsif tags.present?
        @rich_file.tags = tags
        @rich_file.image_tags = tags
        @rich_file.save
        render :json => { :success => true, :image_tags => tags, :uris => @rich_file.uri_cache }
      else
        render :nothing => true, :status => 500
      end
    end

    def destroy
      if(params[:id])
        @rich_file.destroy
        @fileid = params[:id]
      end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def set_rich_file
        @rich_file = RichFile.find(params[:id])
      end
  end
end
