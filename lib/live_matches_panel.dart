import 'dart:async';
import 'package:flutter/material.dart';
import 'supabase_service.dart';
class LiveMatchesPanel extends StatefulWidget {
  final void Function(Map<String,dynamic> match,List<Map<String,dynamic>> servers,int selectedIndex) onServerSelected;
  const LiveMatchesPanel({super.key,required this.onServerSelected});
  @override State<LiveMatchesPanel> createState()=>_LiveMatchesPanelState();
}
class _LiveMatchesPanelState extends State<LiveMatchesPanel>{
  bool loading=true; String? error; List<Map<String,dynamic>> matches=[];
  final Map<String,List<Map<String,dynamic>>> serversByMatch={};
  final Set<String> expandedMatches={},loadingServers={};
  Timer? refreshTimer;
  @override void initState(){super.initState();_load();refreshTimer=Timer.periodic(const Duration(minutes:5),(_)=>_refreshQuietly());}
  Future<void> _refreshQuietly() async {
    try {
      final fresh=await SupabaseService.getLiveMatches();
      if(!mounted)return;
      final validIds=fresh.map((m)=>m['id']?.toString()??'').where((id)=>id.isNotEmpty).toSet();
      serversByMatch.removeWhere((id,_)=>!validIds.contains(id));
      expandedMatches.removeWhere((id)=>!validIds.contains(id));
      setState(()=>matches=fresh);
      for(final id in expandedMatches.toList()){
        if(loadingServers.contains(id))continue;
        loadingServers.add(id);
        try{serversByMatch[id]=await SupabaseService.getLiveMatchServers(id);}catch(_){serversByMatch[id]=[];}
        if(mounted)setState(()=>loadingServers.remove(id));
      }
    }catch(_){/* Keep the last successful schedule visible during temporary network failures. */}
  }
  @override void dispose(){refreshTimer?.cancel();super.dispose();}
  Future<void> _load() async {if(mounted)setState(() { loading=true; error=null; });try{matches=await SupabaseService.getLiveMatches();serversByMatch.clear();expandedMatches.clear();}catch(e){error='تعذر تحميل جدول المباريات: $e';}if(mounted)setState(()=>loading=false);}
  Future<void> _toggle(Map<String,dynamic> match) async {final id=match['id']?.toString()??'';if(id.isEmpty)return;if(expandedMatches.contains(id)){setState(()=>expandedMatches.remove(id));return;}setState(()=>expandedMatches.add(id));if(serversByMatch.containsKey(id)||loadingServers.contains(id))return;setState(()=>loadingServers.add(id));try{serversByMatch[id]=await SupabaseService.getLiveMatchServers(id);}catch(_){serversByMatch[id]=[];}if(mounted)setState(()=>loadingServers.remove(id));}
  String _status(Map<String,dynamic> m){switch((m['match_status']??'scheduled').toString().toLowerCase()){case 'live':case 'in_progress':return 'مباشرة';case 'finished':case 'completed':return 'انتهت';default:return 'لم تبدأ';}}
  Color _statusColor(Map<String,dynamic> m)=>_status(m)=='مباشرة'?Colors.redAccent:_status(m)=='انتهت'?Colors.white54:const Color(0xFFD6AC55);
  String _kickoff(dynamic raw){if(raw==null)return 'موعد غير محدد';final d=DateTime.tryParse(raw.toString())?.toLocal();if(d==null)return 'موعد غير محدد';String two(int n)=>n.toString().padLeft(2,'0');return '${two(d.day)}/${two(d.month)}  ${two(d.hour)}:${two(d.minute)}';}
  Widget _teamCell(String name,dynamic logoUrl){
    final url=logoUrl?.toString().trim()??'';
    return Expanded(child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(url.isEmpty)
        const SizedBox(width:34,height:34,child:Icon(Icons.shield_outlined,color:Color(0xFFD6AC55),size:29))
      else
        SizedBox(width:38,height:38,child:Image.network(url,fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>const Icon(Icons.shield_outlined,color:Color(0xFFD6AC55),size:29))),
      const SizedBox(height:5),
      Text(name,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,
        style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:14)),
    ]));
  }
  @override Widget build(BuildContext context){
    if(loading)return const Center(child:CircularProgressIndicator(color:Color(0xFFD6AC55)));
    if(error!=null)return ListView(children:[const SizedBox(height:90),Center(child:Text(error!,textAlign:TextAlign.center,style:const TextStyle(color:Colors.redAccent))),TextButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('إعادة المحاولة'))]);
    if(matches.isEmpty)return ListView(children:const[ SizedBox(height:100),Icon(Icons.sports_soccer,color:Color(0xFFD6AC55),size:48),SizedBox(height:12),Center(child:Text('لا توجد مباريات متاحة حالياً',style:TextStyle(color:Colors.white70))) ]);
    return RefreshIndicator(color:const Color(0xFFD6AC55),onRefresh:_load,child:ListView.builder(padding:const EdgeInsets.fromLTRB(12,6,12,24),itemCount:matches.length,itemBuilder:(context,index){
      final m=matches[index],id=m['id'].toString(),expanded=expandedMatches.contains(id),servers=serversByMatch[id]??[];
      final hs=m['home_score'],ascore=m['away_score'],hasScore=hs!=null&&ascore!=null;
      return Card(color:const Color(0xFF191919),margin:const EdgeInsets.only(bottom:10),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(13),side:BorderSide(color:expanded?const Color(0xFFD6AC55).withOpacity(.55):Colors.white10)),child:Column(children:[
        InkWell(borderRadius:BorderRadius.circular(13),onTap:()=>_toggle(m),child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
          Row(children:[
            _teamCell(m['home_team']?.toString()??'الفريق الأول',m['home_team_logo_url']),
            Padding(padding:const EdgeInsets.symmetric(horizontal:10),child:Text(hasScore?'$hs : $ascore':'VS',style:const TextStyle(color:Color(0xFFD6AC55),fontWeight:FontWeight.bold,fontSize:17))),
            _teamCell(m['away_team']?.toString()??'الفريق الثاني',m['away_team_logo_url']),
          ]),
          const SizedBox(height:10),Row(children:[Expanded(child:Text(m['competition']?.toString()??'مباراة',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white54,fontSize:11))),Text(_kickoff(m['kickoff_at']),style:const TextStyle(color:Colors.white70,fontSize:11)),const SizedBox(width:10),Text(_status(m),style:TextStyle(color:_statusColor(m),fontSize:11,fontWeight:FontWeight.bold)),const SizedBox(width:5),Icon(expanded?Icons.expand_less:Icons.expand_more,color:const Color(0xFFD6AC55),size:20)])
        ]))),
        if(expanded)...[const Divider(height:1,color:Colors.white12),if(loadingServers.contains(id))const Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator(color:Color(0xFFD6AC55)))else if(servers.isEmpty)const Padding(padding:EdgeInsets.all(14),child:Text('لا توجد سيرفرات بث متاحة لهذه المباراة حالياً',style:TextStyle(color:Colors.white54,fontSize:12)))else Padding(padding:const EdgeInsets.fromLTRB(12,10,12,12),child:Wrap(spacing:8,runSpacing:8,children:List.generate(servers.length,(i){final server=servers[i];return OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFFD6AC55),side:const BorderSide(color:Color(0x66D6AC55))),onPressed:()=>widget.onServerSelected(m,servers,i),icon:const Icon(Icons.play_arrow,size:18),label:Text(server['server_name']?.toString()??'سيرفر ${i+1}'));}))) ]
      ]));
    }));
  }
}
