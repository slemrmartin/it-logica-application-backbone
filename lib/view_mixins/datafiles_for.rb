module ViewMixins
  module DatafilesFor
    def datafiles_for(object, tiny_mce_selector = ".datafile_tinymce", can_upload = true, sub_type = nil)
      render :partial => '/helpers/build_datafiles', :layout => false, :locals => {:object => object, :tiny_mce_selector => tiny_mce_selector, :can_upload => can_upload, :sub_type => sub_type}
    end
  end
end