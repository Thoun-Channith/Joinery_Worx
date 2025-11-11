// lib/app/modules/auth/login_view.dart
// ADD THIS IMPORT AT THE TOP
import '../../routes/app_pages.dart';

class LoginView extends GetView<AuthController> {
  final RxBool isLogin = true.obs;

  LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ... your existing background code ...
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ... your existing app icon and logo code ...

                  // MAIN FORM CARD
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Obx(
                              () => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ... your existing title and subtitle code ...

                              // FORM FIELDS
                              if (!isLogin.value)
                                _buildTextField(
                                  hintText: 'Full Name',
                                  controller: controller.nameController,
                                  prefixIcon: Icons.person_outline,
                                ),
                              if (!isLogin.value) const SizedBox(height: 16),

                              _buildTextField(
                                hintText: 'Email',
                                controller: controller.emailController,
                                prefixIcon: Icons.email_outlined,
                              ),
                              const SizedBox(height: 16),

                              _buildPasswordTextField(),
                              const SizedBox(height: 24),

                              // SIGN IN/UP BUTTON
                              Obx(() => ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                  backgroundColor: AppTheme.primaryLightBlue,
                                ),
                                onPressed: controller.isLoading.value
                                    ? null
                                    : () async {
                                  if (isLogin.value) {
                                    await controller.login();
                                  } else {
                                    await controller.createUser();
                                  }
                                },
                                child: controller.isLoading.value
                                    ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : Text(
                                  isLogin.value ? 'Sign In' : 'Sign Up',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )),
                              const SizedBox(height: 24),

                              // SWITCH BETWEEN LOGIN/SIGNUP
                              Center(
                                child: TextButton(
                                  onPressed: controller.isLoading.value
                                      ? null
                                      : () => isLogin.value = !isLogin.value,
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

// ... your existing _buildTextField and _buildPasswordTextField methods ...
}