Rails.application.config.after_initialize do
  AppsController.prepend(Module.new do
    def show
      if params[:name] == 'opencomposer' && params[:type] == 'sys'
        render 'apps/opencomposer_embed'
      else
        super
      end
    end
  end)
end
