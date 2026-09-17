import 'package:flutter/material.dart';

import 'custom_bottom_nav.dart';

class MyApp extends StatelessWidget{
  const MyApp({super.key});

  

  @override
  Widget build (BuildContext context){

    return SafeArea(
      child: Scaffold(
        // body: ,
        bottomNavigationBar: const CustomBottomNav(),
        
      ),
    );
  }
}