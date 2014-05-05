# coding: utf-8

# Studython (Study Seesaw/Study Pin)
#  2014-01-18 ko.kaneko

require "rubygems"
require "bundler/setup"
Bundler.require(:default)
#%w(sinatra slim dm-core dm-migrations
#   dm-timestamps dm-types dm-aggregates date json).each  { |lib| require lib}

#data-mapper
db_path = File.dirname(__FILE__) + "/studython.db"
DataMapper.setup(:default, 'sqlite3:' + db_path)
class Project
    include DataMapper::Resource
    property :proj_id, Serial
    property :proj_name, String
    property :str_date, DateTime
    property :end_date, DateTime
    property :numbers, Integer
    has n, :users
end
class User
    include DataMapper::Resource
    property :user_id, Serial
    property :user_name, String
    property :login_id, String ,:unique => true
    property :proj_id, Integer
    property :created, DateTime
    belongs_to :project
    has n, :transactions
end
class Transaction
    include DataMapper::Resource
    property :tran_id, Serial
    property :datetime, DateTime
    property :user_id, String
    property :point, Integer
    property :comment, String
    belongs_to :user
end
DataMapper.auto_upgrade!

#helper
def GetUserAndProject(login_id, reference_usr_id = nil)
    usr = User.first(:login_id => login_id)
    raise 'Your "loginId" is not valid' unless usr
    raise 'Projects are not found' unless usr.project
    return usr unless reference_usr_id

    ref_usr = User.first(:user_id => reference_usr_id)
    raise 'You do not have the permission to reference' unless ref_usr
    raise 'You do not have the permission to reference' unless ref_usr.project
    raise 'You do not have the permission to reference' unless ref_usr.project.proj_id == usr.project.proj_id
    return ref_usr
end

def IsMobile(user_agent)
    /iPhone|iPod|Android/ =~ user_agent
end

def FormatHHMM(min,zero='')
    return zero if min == 0
    s = (min >= 0 ? "" : "-")
    min = min.abs
    s = (min/60 >= 1 ? (min/60).floor.to_s + "H ":"") + (min%60 > 0 ? (min%60).to_s + "m ":"");
end

#sinatra
disable :show_exceptions
enable :inline_templates#, :sessions

## sinatra純正のsessionではiOSでcookieのsession管理がうまくいかないため、Rackを使う
use Rack::Session::Cookie, :key => 'rack.session',
                           #:domain => 'xxx',
                           :path => '/',
                           :expire_after => 60*60*24*14, # 2 weeks
                           :secret => 'abcdef'

get '/' do
    raise 'Please set "/start/{:login_id}" at end of this URL'
end

get '/start/:login_id' do
    user = GetUserAndProject(params[:login_id])

    if (user.project.end_date) then
        remain_days = (user.project.end_date.to_date - Date.today).to_i
    else
        remain_days = -1
    end

    Slim_vals = Struct.new(:today, :isMobile, :project, :user, :remain_days)
    @slim_vals = Slim_vals.new(Date.today, IsMobile(request.user_agent), user.project, user, remain_days)

    slim :start
end

get '/entry/:login_id' do
    user = GetUserAndProject(params[:login_id])

    session[:login_id] = user.login_id

    Slim_vals = Struct.new(:today, :isMobile, :project, :user)
    @slim_vals = Slim_vals.new(Date.today, IsMobile(request.user_agent), user.project, user)

    slim :entry
end

post '/addrecord' do
    raise 'ログインしていません' unless session[:login_id]

    user = GetUserAndProject(session[:login_id])
    user.transactions << Transaction.create(:datetime => DateTime.now,
                                            :user_id => user.user_id,
                                            :point => params['SpendTime'],
                                            :comment => params['comment'])
    user.save

    redirect '/ranking'
end

post '/nothanks' do
    redirect '/ranking'
end

get '/ranking' do
    raise 'ログインしていません' unless session[:login_id]

    user = GetUserAndProject(session[:login_id])

    members = User.all(:proj_id => user.project.proj_id)
    members.each { |member|
        class << member
            attr_accessor :total, :today
        end
        member.total = Transaction.sum(:point, :user_id => member.user_id) || 0
        member.today = Transaction.sum(:point, :user_id => member.user_id,
                                     :datetime.gte => Date.today.strftime("%Y-%m-%d")) || 0
    }
    members.sort!{|a,b| -1 * (a.total <=> b.total)}

    Slim_vals = Struct.new(:today, :isMobile, :project, :user, :members)
    @slim_vals = Slim_vals.new(Date.today, IsMobile(request.user_agent), user.project, user, members)

    slim :ranking
end

get '/history/:ref_user_id' do
    raise 'ログインしていません' unless session[:login_id]

    ref_user = GetUserAndProject(session[:login_id],params[:ref_user_id])

    class << ref_user
        attr_accessor :total
    end
    ref_user.total = Transaction.sum(:point, :user_id => ref_user.user_id) || 0
    ref_user.transactions.sort!{|a,b| -1 * (a.datetime <=> b.datetime)}

    Slim_vals = Struct.new(:today, :isMobile, :project, :ref_user, :trans)
    @slim_vals = Slim_vals.new(Date.today, IsMobile(request.user_agent), ref_user.project, ref_user, ref_user.transactions)

    slim :history
end

get '/heatmapcal/:ref_user_id' do
    raise 'ログインしていません' unless session[:login_id]

    ref_user = GetUserAndProject(session[:login_id],params[:ref_user_id])

    day = Date.today
    startDay = Date.new(day.year, day.month, 1) >> -1
    endDay = (Date.new(day.year, day.month, 1) >>1) - 1
    day_values = {}
    (startDay..endDay).each do |d|
        day_values[d.to_time.to_i.to_s] = Transaction.sum(:point,
                                                          :user_id => ref_user.user_id,
                                                          :datetime.gte => d.strftime("%Y-%m-%d"),
                                                          :datetime.lt => (d + 1).strftime("%Y-%m-%d")) || 0
    end

    day_values_json = day_values.to_json    # slimテンプレートでダブルコーテーションがエンコードされないように式展開で#{{}}を使うこと

    Slim_vals = Struct.new(:today, :isMobile, :project, :ref_user, :dayvals)
    @slim_vals = Slim_vals.new(Date.today, IsMobile(request.user_agent), ref_user.project, ref_user, day_values_json)

    slim :heatmapcal
end

# get '/logout' do
#     session.delete(:loginId)
#     session.clear
#     'ありがとうございました'
# end

not_found do
  'サイトがみつかりません'
end

error do
  'エラーが発生しました。 - ' + env['sinatra.error'].message
end

__END__

@@layout
doctype html
html.responsive
    head
        meta charset="utf-8"
        meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=0"
        /! Always force latest IE rendering engine or request Chrome Frame
        meta content="IE=edge,chrome=1" http-equiv="X-UA-Compatible"
        meta http-equiv="Cache-Control" content="no-cache"
        meta http-equiv="Pragma" content="no-cache"
        meta http-equiv="Expires" content="0"
        link rel="shortcut icon" type="image/gif" href="/favicon.ico"
        link rel="stylesheet" type="text/css" href="/xtyle/css/xtyle.css"
        script src="http://ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js"
        /! script src="/xtyle/js/xtyle.js"
        title == "Studython"
        javascript:
            function close_win(){
               var nvua = navigator.userAgent;
                if(nvua.indexOf('MSIE') >= 0){
                  if(nvua.indexOf('MSIE 5.0') == -1) {
                    top.opener = '';
                  }
                }
                else if(nvua.indexOf('Gecko') >= 0){
                  top.name = 'CLOSE_WINDOW';
                  wid = window.open('','CLOSE_WINDOW');
                }
                top.close();

              //location.href = '/logout';
            }
        - if @slim_vals.isMobile
            css:
                .firstDiv {
                    margin-top:0px;
                    padding:20px;
                }
        - else
            css:
                .firstDiv {
                    margin-top:60px;
                    padding:20px;
                }
    body.bg-light
        nav#title.large.border-bottom
            div.layout-fixed-center
                div.grid
                    div
                        span.logo style="float: left;" #{@slim_vals.project.proj_name}
                    div
                        span.logo style="float: left;" #{@slim_vals.today}
                    div
                        button#close.info.border-radius type="button" style="width: 100px; background-color: black;" onClick="close_win()" × close
        div.layout-fixed-center
            == yield
        div.footer style="height:50px;"

@@start
div.firstDiv
    - if @slim_vals.remain_days > 0
        h2
            | You have #{"only " if @slim_vals.remain_days < 10}
            span style="font-size: 250%;" #{@slim_vals.remain_days}
            |  day#{"s" unless @slim_vals.remain_days == 1} remain.

    h2 Please push start button.
    div.margin style="margin-top:30px;"
        button#next.info.border-radius.margin type="button" style="width: 250px; background-color: dodgerblue;" onClick="location.href ='/entry/#{@slim_vals.user.login_id}'" Start

@@entry
javascript:
        function spendTimeCalc(addTime){
            var m = (window.form_addrec.SpendTime.value || 0) - 0;
            m = m + addTime;
            var l = (m/60 >= 1 ? Math.floor(m/60) + "H ":"") + (m%60 > 0 ? (m%60) + "m ":"");
            window.form_addrec.SpendTime.value = m;
            window.form_addrec.SpendTimeLbl.value = l;
        }
        function spendTimeClear(){
            window.form_addrec.SpendTime.value = 0;
            window.form_addrec.SpendTimeLbl.value = "";
        }
div.firstDiv
    h2 Hello #{@slim_vals.user.user_name} !!
div#form-addrec.margin.border-bottom
    form.margin name="form_addrec" action="/addrecord" method="post"
        div
            | 本日の勉強時間を入力してください
        input#spendtime-lbl type="text" name="SpendTimeLbl" readonly="true" style="text-align: center;"
        input#spendtime type="hidden" name="SpendTime"
        div.grid
            button#plusOneHour.info.border-radius type="button" style="width: 88px; margin:2px; background-color: deepskyblue;" onClick="spendTimeCalc(60)" +1H
            button#plusTenMin.info.border-radius type="button" style="width: 88px; margin:2px; background-color: deepskyblue;" onClick="spendTimeCalc(10)" +10m
            button#clearTime.attention.border-radius type="button" style="width: 88px; margin:2px;" onClick="spendTimeClear()" Clear
        br
        div
            | あればコメントを入れます
        textarea#comment name="comment"
        br
        input#submit type="submit" value="GO"
div#form-nothanks.grid.margin
    form.margin action="/nothanks" method="post"
        div
            | スキップする
        input#submit type="submit" value="No, Thanks"


@@ranking
div.firstDiv
   h2 Ranking
div#form-ranking.grid.margin
- @slim_vals.members.each_with_index do |member,index|
    - if @slim_vals.user.user_id == member.user_id
        - c_border = "#ffcc0e"
    - else
        - c_border = "#8a8a8a"

    - case index+1
    - when 1
        - c_rank = "1st"
    - when 2
        - c_rank = "2nd"
    - when 3
        - c_rank = "3rd"
    - else
        - c_rank = (index+1).to_s + "th"

    - @toprunner = member.total if index == 0

    div.grid.margin.border.border-radius style="background-color: #ffffff; width: 300px; margin-left: auto; margin-right: auto; border: 2px solid #{c_border}; cursor: pointer;" onClick="location.href = '/history/#{member.user_id}';"
        div.grid1
            p style="font-size: 125%; text-align: center;"
                | #{c_rank}

        div.grid10.skip4
            strong
                p style="margin-left: 20px; font-size: 200%; text-align: center;"
                    | #{member.user_name}
            hr

        div.grid10.skip6
            strong
                p style="margin-right: 20px; font-size: 200%; text-align: center;"
                    | #{FormatHHMM(member.total,"0H")}
            hr

        div.grid10.skip2
            p style="font-size: 100%; color: gainsboro; text-align: center;"
                | Today
        div.grid10.skip3
            p style="font-size: 100%; color: grey; text-align: center;"
                | #{FormatHHMM(member.today)}
        div.grid10.skip2
            p style="font-size: 100%; color: gainsboro; text-align: center;"
                | Behind
        div.grid10.skip3
            p style="font-size: 100%; color: grey; text-align: center;"
                | #{FormatHHMM(member.total - @toprunner)}


@@history
div.firstDiv
    h2 #{@slim_vals.ref_user.user_name}'s activity
    div.grid
        div.grid2 style = "width:50%; text-align: left;"
            a href="#" onClick="history.back(); return false;" style="font-size: 140%;" ←back
        div.grid2 style = "width:50%; text-align: right;"
            a href="/heatmapcal/#{@slim_vals.ref_user.user_id}" style="font-size: 140%;" calender→
div#historylist.border.border-radius.margin
    table style="width: 100%;"
        thead
            tr
                th 日付
                th 時間
                th コメント
        tbody
            tr.info
                td Total
                td #{FormatHHMM(@slim_vals.ref_user.total)}
                td
        - @slim_vals.trans.each do |tran|
            tr style="background-color: #ffffff;"
                - if @slim_vals.isMobile
                    td #{tran.datetime.strftime("%m/%d")}
                    td #{FormatHHMM(tran.point)}
                    td #{tran.comment}
                - else
                    td width="150px" #{tran.datetime.strftime("%Y/%m/%d  %H:%M")}
                    td width="150px" + #{FormatHHMM(tran.point)}
                    td #{tran.comment}

@@heatmapcal
script type="text/javascript" src="//d3js.org/d3.v3.min.js"
script type="text/javascript" src="//cdn.jsdelivr.net/cal-heatmap/3.3.10/cal-heatmap.min.js"
link rel="stylesheet" href="//cdn.jsdelivr.net/cal-heatmap/3.3.10/cal-heatmap.css"

div.firstDiv
    h2 #{@slim_vals.ref_user.user_name}'s active calender
    a href="#" onClick="history.back(); return false;" style="font-size: 140%;" ←back

div#calender.border-radius style="padding:20px; width: 220px; margin-left: auto; margin-right: auto; background: white;"

javascript:
    var cal = new CalHeatMap();
    cal.init({
        itemSelector: "#calender",
        domain: "month",
        subDomain: "x_day",
        data: #{{@slim_vals.dayvals}},
        cellSize: 30,
        range: 2,
        verticalOrientation: true,
        legend: [40, 80, 120, 160, 200, 240],
        legendColors: {
        empty: "#ededed",
        min: "#e0ffff",
        max: "#0066FF"
        }
    });
    cal.previous();
