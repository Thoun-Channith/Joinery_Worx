import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import 'auth_controller.dart';

class LoginView extends GetView<AuthController> {
  // This RxBool allows switching between Login and Sign Up forms.
  final RxBool isLogin = true.obs;

  LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    // Gets the screen size for responsive UI adjustments.
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // background header.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: size.height * 0.55,
              decoration: const BoxDecoration(
                color: Color(0xFFEDE8D0),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Icon Section
                  const SizedBox(height: 60),
                  // _buildAppIcon(),
                  Image.asset("assets/icons/O-logo.png", height: 120,),
                  const SizedBox(height: 25),
                  SvgPicture.asset(
                    'assets/icons-svg/text-logo.svg',
                    width: 256,
                    colorFilter: const ColorFilter.mode(
                      AppTheme.primaryDarkBlue,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(height: 25),
                  // This is the main white card for the login form.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        // Obx makes the widget rebuild when isLogin changes.
                        child: Obx(
                          () => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                isLogin.value
                                    ? 'Welcome Back.'
                                    : 'Create Account.',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isLogin.value
                                    ? 'Sign in to continue tracking your activity.'
                                    : 'Sign up to get started today.',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Shows 'Full Name' field only on the Sign Up form.
                              if (!isLogin.value)
                                _buildTextField(
                                  hintText: 'Full Name',
                                  controller: controller.nameController,
                                  prefixIcon: Icons.person_outline,
                                ),
                              if (!isLogin.value) const SizedBox(height: 16),

                              // Email/Username field
                              _buildTextField(
                                hintText: 'Username or Email',
                                controller: controller.emailController,
                                prefixIcon: Icons.email_outlined,
                              ),
                              const SizedBox(height: 16),

                              // Password field with the visibility toggle
                              _buildPasswordTextField(),
                              const SizedBox(height: 24),

                              // Main Sign In or Sign Up button
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                  backgroundColor: AppTheme.primaryLightBlue,
                                ),
                                onPressed: () {
                                  // Calls the correct function from the controller
                                  if (isLogin.value) {
                                    controller.login();
                                  } else {
                                    controller.createUser();
                                  }
                                },
                                child: Text(
                                  isLogin.value ? 'Sign In' : 'Sign Up',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,

                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // The button to switch between the two forms
                              Center(
                                child: TextButton(
                                  onPressed: () =>
                                      isLogin.value = !isLogin.value,
                                  child: Text(
                                    isLogin.value
                                        ? "Don't have an account? Sign Up"
                                        : "Already have an account? Sign In",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A helper widget to build the app icon and title.
  Widget _buildAppIcon() {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A67F0),
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                Positioned(
                  left: 0,
                  child: Container(
                    width: 32,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3D3BB1),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(32),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'STAFF TRACKER',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // A reusable widget for standard text fields (like email and name).
  Widget _buildTextField({
    required String hintText,
    required TextEditingController controller,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        // The prefix icon you requested.
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: const Color(0xFF9CA3AF))
            : null,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  // A specific widget for the password field to handle the visibility toggle.
  Widget _buildPasswordTextField() {
    // Obx rebuilds this widget when controller.isPasswordHidden changes.
    return Obx(
      () => TextFormField(
        controller: controller.passwordController,
        obscureText: controller.isPasswordHidden.value,
        decoration: InputDecoration(
          hintText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF9CA3AF)),
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          // The clickable suffix icon for password visibility.
          suffixIcon: IconButton(
            icon: Icon(
              controller.isPasswordHidden.value
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF9CA3AF),
            ),
            onPressed: controller.togglePasswordVisibility,
          ),
        ),
      ),
    );
  }
}
