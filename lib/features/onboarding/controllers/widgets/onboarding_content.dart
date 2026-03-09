import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:rojava/data/model/onboarding_page_model.dart';

class OnboardingContent extends StatelessWidget {
  final OnboardingPage page;

  const OnboardingContent({Key? key, required this.page}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (page.animationPath.isNotEmpty)
          Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  page.primaryColor.withOpacity(0.3),
                  page.primaryColor.withOpacity(0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
            child: Center(
              child: Lottie.asset(
                page.animationPath,
                width: 250,
                height: 250,
                fit: BoxFit.contain,
              ),
            ),
          ),

        const SizedBox(height: 60),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
              shadows: [
                Shadow(
                  color: page.primaryColor.withOpacity(0.5),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            page.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
