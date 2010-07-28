module TimeZone
  def time_zone_from_ip(ip)
    begin
      location = open("http://api.hostip.info/get_html.php?ip=#{ip}&position=true")
      if location.string =~ /Latitude: (.+?)\nLongitude: (.+?)\n/
        timezone = Geonames::WebService.timezone($1, $2)
        ActiveSupport::TimeZone::MAPPING.index(timezone.timezone_id) unless timezone.nil?
    end
    rescue 
      nil
    end 
  end
end
