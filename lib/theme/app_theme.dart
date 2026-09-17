import 'package:flutter/material.dart';

class AppTheme {

 //LIGHT THEME
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF7FDFC),
    fontFamily: 'Inter',
    extensions: const [
      CustomAppColors(
        backgroundColor:  Color(0xFFF7FDFC), // const Color.fromRGBO( 249,253,253,1, ); 
        searchbarColor:   Color(0xFFFDFDFD),
        headingTextColor: Color(0xFF010B27, ), //const Color(0xFF14243C);,
        suheadingTextColor: Color(0xFF15273C),
        descriptionColor: Color(0xFF6D819C),
        cardColor: Color(0xFFFDFEFF),
        bottomnaveColor: Color(0xFFFFFEFF),
        buttonColor: Color(0xFF129D7C),
        longRectangleColor: Color(0xFFECF6F5),
        septemberColor: Color(0xFF0D5F4D),
        borderColor: Color(0xFFE3EBE8)  //border
      ),
    ],
  );

  //DARK THEME
  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0F14),
    fontFamily: 'Inter',
    extensions: const [
      CustomAppColors(
        backgroundColor:  Color(0xFF0A0F14),
        searchbarColor: Color(0xFF151B24),
        headingTextColor: Color(0xFFFFFEFF),
        suheadingTextColor: Color(0xFFBDDFFF),
        descriptionColor: Color(0xFFA3C5E1),
        cardColor: Color(0xFF131820),
        bottomnaveColor: Color(0xFF1FBD81),
        buttonColor: Color(0xFF29E0A2),
        longRectangleColor: Color(0xFF121A23),
        septemberColor: Color(0xFFE4EBF9),
        borderColor : Color(0xFF273541),   // border
      )
    ]
  );
}

class CustomAppColors extends ThemeExtension<CustomAppColors> {
  final Color backgroundColor;
  final Color searchbarColor;
  final Color headingTextColor;
  final Color suheadingTextColor;
  final Color descriptionColor;
  final Color cardColor;
  final Color bottomnaveColor;
  final Color buttonColor;
  final Color longRectangleColor;
  final Color septemberColor;
  final Color borderColor;

  const CustomAppColors({
    required this.backgroundColor,
    required this.searchbarColor,
    required this.headingTextColor,
    required this.suheadingTextColor,
    required this.descriptionColor,
    required this.cardColor,
    required this.bottomnaveColor,
    required this.buttonColor,
    required this.longRectangleColor,
    required this.septemberColor,
    required this.borderColor,
   
  });

  @override
  CustomAppColors copyWith({
    Color? backgroundColor,
    Color? searchbarColor,
    Color? headingTextColor,
    Color? suheadingTextColor,
    Color? descriptionColor,
    Color? cardColor,
    Color? bottomnaveColor,
    Color? buttonColor,
    Color? longRectangleColor,
    Color? septemberColor,
    Color? borderColor,
  }) {
    return CustomAppColors(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      searchbarColor: searchbarColor ?? this.searchbarColor,
      headingTextColor: headingTextColor ?? this.headingTextColor,
      suheadingTextColor: suheadingTextColor ?? this.suheadingTextColor,
      descriptionColor: descriptionColor ?? this.descriptionColor,
      cardColor: cardColor ?? this.cardColor,
      bottomnaveColor: bottomnaveColor ?? this.bottomnaveColor,
      buttonColor: buttonColor ?? this.buttonColor,
      longRectangleColor: longRectangleColor ?? this.longRectangleColor,
      septemberColor: septemberColor ?? this.septemberColor,
      borderColor: borderColor ?? this.borderColor,
    );
  }

  @override
  ThemeExtension<CustomAppColors> lerp(
    covariant ThemeExtension<CustomAppColors>? other,
    double t,
  ) {
    return this;
  }
}

extension CustomAppColorsX on BuildContext {
  CustomAppColors get myAppColors => Theme.of(this).extension<CustomAppColors>()!;
}





// import 'package:flutter/material.dart';
// class AppThemee{
//   // ─────────────────────────
//   // LIGHT THEME
//   // ─────────────────────────

//   static const lightBackground = Color(0xFFF7FAF9); //background
//   static const lightSurface = Color(0xFFFFFFFF);  //searchbar background
//   static const lightSurfaceSecondary = Color(0xFFF1F5F4); // cardbackground color 


//   static const lightPrimary = Color(0xFF16B886);  //rnd_rectangle
//   static const lightPrimaryDark = Color(0xFF07866A); //long_rectangle
//   static const lightPrimaryLight = Color(0xFFD8F7ED); //

//   static const lightTextPrimary = Color(0xFF172A3A);
//   static const lightTextSecondary = Color(0xFF63788B);
//   static const lightTextTertiary = Color(0xFF8A9AAA);
//   static const lightTextDisabled = Color(0xFFB2BEC7);


//   // ─────────────────────────
//   // DARK THEME
//   // ─────────────────────────

//   static const darkBackground = Color(0xFF080D11);  //background
//   static const darkSurface = Color(0xFF10171E);     //searchbar background
//   static const darkSurfaceSecondary = Color(0xFF151E27); //


//   static const darkPrimary = Color(0xFF19D39B);     //rnd_rectangle
//   static const darkPrimaryDark = Color(0xFF0E9F78); //
//   static const darkPrimaryLight = Color(0xFF12382F);

//   static const darkTextPrimary = Color(0xFFF4F8FA);  //all document types text
//   static const darkTextSecondary = Color(0xFFA9BBCB); //
//   static const darkTextTertiary = Color(0xFF718597);
//   static const darkTextDisabled = Color(0xFF526474);


//   // ─────────────────────────
//   // TOOL COLORS
//   // ─────────────────────────

//   static const scan = Color(0xFF19B987);
//   static const imagePdf = Color(0xFF3B82F6);
//   static const pdfImage = Color(0xFF8B5CF6);
//   static const excel = Color(0xFF16A765);


//   // ─────────────────────────
//   // FILE TYPES
//   // ─────────────────────────

//   static const pdf = Color(0xFFEF4444);
//   static const image = Color(0xFF3B82F6);
//   static const text = Color(0xFF8B5CF6);

  

//   static ThemeData light = ThemeData(
//     brightness: Brightness.light,
//     scaffoldBackgroundColor: lightBackground,
//     fontFamily: 'Inter',
//     colorScheme: const ColorScheme.light(
//       primary: lightPrimary,
//       surface: lightSurface  ),
//     extensions: const [
//       CustomAppColorsss(
//         lightSurface: lightSurface , 
//         lightSurfaceSecondary: lightSurfaceSecondary, 
//         lightBackground: lightBackground , 
//         lightBorder: lightBorder, 
//         lightPrimary: lightSurface, 
//         lightPrimaryDark: lightPrimaryDark, 
//         lightPrimaryLight: lightPrimaryLight , 
//         lightTextPrimary: lightTextPrimary , 
//         lightTextSecondary: lightTextSecondary , 
//         lightTextTertiary: lightTextTertiary, 
//         lightTextDisabled: lightTextDisabled, 
//         scan: scan, imagePdf: scan, pdfImage: scan, excel: scan     
//       )
//     ]
    
//   );

//   static ThemeData dark = ThemeData(
//     brightness : Brightness.dark,
//     scaffoldBackgroundColor : darkBackground,
//     fontFamily: 'Inter',
//     colorScheme: const ColorScheme.dark(
//       primary: darkPrimary,
//       surface: darkSurface),
//     extensions: const [
//       CustomAppColorsss(lightSurface: darkSurface, 
//       lightSurfaceSecondary: darkSurfaceSecondary, 
//       lightBackground: darkBackground, 
//       lightBorder: darkBorder, 
//       lightPrimary: darkPrimary, 
//       lightPrimaryDark: darkPrimaryDark, 
//       lightPrimaryLight: darkPrimaryLight, 
//       lightTextPrimary: darkTextPrimary, 
//       lightTextSecondary: darkTextSecondary, 
//       lightTextTertiary: darkTextTertiary, 
//       lightTextDisabled: darkTextDisabled, 
//       scan: scan, 
//       imagePdf: imagePdf, 
//       pdfImage: pdfImage, 
//       excel: excel)
//     ]  

//   );

// }



// class CustomAppColorsss extends ThemeExtension<CustomAppColorsss>{
//   final Color lightBackground;
//   final Color lightSurface ;
//   final Color lightSurfaceSecondary;
//   final Color lightBorder;
//   final Color lightPrimary;
//   final Color lightPrimaryDark;
//   final Color lightPrimaryLight;
//   final Color lightTextPrimary;
//   final Color lightTextSecondary;
//   final Color lightTextTertiary;
//   final Color lightTextDisabled;
//   final Color scan;
//   final Color imagePdf;
//   final Color pdfImage;
//   final Color excel;


//   const CustomAppColorsss ({
//     required this.lightSurface,
//     required this.lightSurfaceSecondary, 
//     required this.lightBackground, 
//     required this.lightBorder, 
//     required this.lightPrimary, 
//     required this.lightPrimaryDark, 
//     required this.lightPrimaryLight, 
//     required this.lightTextPrimary, 
//     required this.lightTextSecondary, 
//     required this.lightTextTertiary, 
//     required this.lightTextDisabled, 
//     required this.scan, 
//     required this.imagePdf, 
//     required this.pdfImage, 
//     required this.excel,
//   });

//   @override
//   CustomAppColorsss copyWith({
//     Color? lightSurface,
//     Color? lightSurfaceSecondary
//   }){
//     return CustomAppColorsss(
//     lightBackground: lightBackground , 
//     lightSurface: lightSurface ?? this.lightSurface,
//     lightSurfaceSecondary: lightSurfaceSecondary ?? this.lightSurfaceSecondary, 
//     lightBorder: lightBorder  , 
//     lightPrimary: lightPrimary , 
//     lightPrimaryDark: lightPrimaryDark  , 
//     lightPrimaryLight: lightPrimaryLight  , 
//     lightTextPrimary: lightTextPrimary , 
//     lightTextSecondary: lightTextSecondary  , 
//     lightTextTertiary: lightTextTertiary  , 
//     lightTextDisabled: lightTextDisabled, 
//     scan: scan, 
//     imagePdf: imagePdf, 
//     pdfImage: pdfImage, 
//     excel: excel  
//     );
  
//   }

//   @override
//   ThemeExtension<CustomAppColorsss> lerp(covariant ThemeExtension<CustomAppColorsss>? other, double t) {
//     return this;
//   }
// }